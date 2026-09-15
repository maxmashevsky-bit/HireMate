import AppKit
import ScreenCaptureKit
import SwiftUI
import Observation

enum OverlayCaptureCompatibility: Equatable {
    case notTested
    case running
    case excluded
    case captured
    case failed(String)

    var title: String {
        switch self {
        case .notTested: "Не проверено"
        case .running: "Проверяем…"
        case .excluded: "В этом тесте окно не попало в снимок"
        case .captured: "Окно попало в снимок"
        case .failed(let message): "Проверка не завершена: \(message)"
        }
    }
}

@MainActor
protocol OverlayCompatibilityTesting {
    func containsTestMarker(on displayID: CGDirectDisplayID) async throws -> Bool
}

@MainActor
private final class NativeOverlayCompatibilityTester: OverlayCompatibilityTesting {
    func containsTestMarker(on displayID: CGDirectDisplayID) async throws -> Bool {
        guard CGPreflightScreenCaptureAccess() else { throw ScreenCaptureError.permission }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureError.missingSource
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false
        configuration.capturesAudio = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        return Self.containsMarker(in: image)
    }

    private static func containsMarker(in image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return false }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var magenta = 0
        var cyan = 0
        for offset in stride(from: 0, to: pixels.count, by: 8) {
            let red = pixels[offset]
            let green = pixels[offset + 1]
            let blue = pixels[offset + 2]
            if red > 210, green < 90, blue > 170 { magenta += 1 }
            if red < 90, green > 210, blue > 170 { cyan += 1 }
            if magenta >= 200, cyan >= 200 { return true }
        }
        return false
    }
}

@MainActor
private final class CopilotPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}

@MainActor @Observable
final class OverlayController: NSObject, NSWindowDelegate {
    let preferences = OverlayPreferences()
    let hotkeys = GlobalHotkeyService()
    let teleprompter = TeleprompterController()
    private let compatibilityTester: any OverlayCompatibilityTesting
    private weak var model: AppModel?
    var openMainWindow: (() -> Void)?
    private var panel: CopilotPanel?
    private var screenObserver: NSObjectProtocol?
    private var compatibilityTask: Task<Void, Never>?
    private var isRestoringFrame = false
    private(set) var connectedScreenCount = NSScreen.screens.count
    private(set) var isVisible = false
    private(set) var isClickThrough = false
    private(set) var focusRequest = 0
    private(set) var historyScrollRequest = 0
    private(set) var historyScrollDirection = 1
    private(set) var isChatRailVisible = true
    private(set) var isNotesPanelVisible = false
    private(set) var compatibilityResult: OverlayCaptureCompatibility = .notTested
    private(set) var isCompatibilityMarkerVisible = false

    var restoreInputHint: String {
        preferences.restoreInputHint(focusShortcutRegistered: hotkeys.registeredActions.contains(.focus))
    }

    init(compatibilityTester: (any OverlayCompatibilityTesting)? = nil) {
        self.compatibilityTester = compatibilityTester ?? NativeOverlayCompatibilityTester()
    }

    func connect(model: AppModel) {
        self.model = model
        teleprompter.connect(app: model)
        configureHotkeys()
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.connectedScreenCount = NSScreen.screens.count
                self?.keepOnVisibleScreen()
                self?.saveFrame()
            }
        }
    }

    func configureHotkeys() {
        hotkeys.configure(enabled: preferences.shortcutsEnabled, preset: preferences.shortcutPreset,
                          overrides: preferences.hotkeyOverrides,
                          disabledActionIDs: Set(preferences.disabledHotkeyActions.compactMap(UInt32.init))) { [weak self] in
            self?.perform($0)
        }
    }

    func toggle() { isVisible ? hide() : show() }
    func show() {
        guard let model else { return }
        let window: CopilotPanel
        if let panel { window = panel }
        else {
            window = CopilotPanel(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                                  styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
            window.title = "Max Interview Copilot — подсказки"
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.sharingType = .none
            window.hasShadow = true
            window.minSize = NSSize(width: 640, height: 500)
            window.delegate = self
            window.contentView = NSHostingView(rootView: OverlayView(model: model, controller: self))
            panel = window
        }
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let area = screen.visibleFrame
            let defaultFrame = NSRect(x: area.maxX - 884, y: area.maxY - 644, width: 860, height: 620)
            restoreFrame(preferences.savedFrame(for: screen, minimumSize: window.minSize) ?? defaultFrame, on: screen)
        }
        applyOpacity()
        window.ignoresMouseEvents = isClickThrough
        window.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        saveFrame()
        panel?.orderOut(nil)
        isVisible = false
    }

    func openMain(_ section: AppSection) {
        model?.requestedSection = section
        hide()
        NSApp.activate(ignoringOtherApps: true)
        if let openMainWindow { openMainWindow() }
        else if let main = NSApp.windows.first(where: { $0.canBecomeMain }) {
            main.makeKeyAndOrderFront(nil)
        }
    }

    func toggleClickThrough() {
        isClickThrough.toggle()
        panel?.ignoresMouseEvents = isClickThrough
        if isClickThrough { panel?.resignKey() }
    }

    func focusInput() {
        if !isVisible { show() }
        isClickThrough = false
        panel?.ignoresMouseEvents = false
        panel?.makeKey()
        focusRequest += 1
    }

    func toggleNotesPanel() {
        if !isVisible { show() }
        isNotesPanelVisible.toggle()
        if isNotesPanelVisible { Task { await model?.notes.refresh() } }
    }

    func applyOpacity() {
        panel?.alphaValue = isCompatibilityMarkerVisible ? 1 : CGFloat(min(1, max(0.35, preferences.opacity)))
    }

    func startDragging(_ event: NSEvent) { panel?.performDrag(with: event) }

    func testCaptureCompatibility() {
        guard compatibilityTask == nil else { return }
        guard CGPreflightScreenCaptureAccess() else {
            compatibilityResult = .failed(ScreenCaptureError.permission.localizedDescription)
            return
        }
        let wasVisible = isVisible
        if !wasVisible { show() }
        guard let panel, let displayID = panel.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            compatibilityResult = .failed("Не удалось определить дисплей рабочего окна.")
            if !wasVisible { hide() }
            return
        }
        compatibilityResult = .running
        isCompatibilityMarkerVisible = true
        applyOpacity()
        panel.sharingType = .readOnly
        panel.displayIfNeeded()
        compatibilityTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                panel.sharingType = .none
                isCompatibilityMarkerVisible = false
                applyOpacity()
                compatibilityTask = nil
                if !wasVisible { hide() }
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
                let controlMarkerFound = try await compatibilityTester.containsTestMarker(on: displayID)
                guard controlMarkerFound else {
                    compatibilityResult = .failed("Контрольный снимок не распознал тестовый маркер.")
                    return
                }
                panel.sharingType = .none
                try await Task.sleep(for: .milliseconds(250))
                let markerFound = try await compatibilityTester.containsTestMarker(on: displayID)
                try Task.checkCancellation()
                compatibilityResult = markerFound ? .captured : .excluded
            } catch is CancellationError {
                compatibilityResult = .notTested
            } catch {
                compatibilityResult = .failed((error as? LocalizedError)?.errorDescription ?? "ScreenCaptureKit вернул ошибку.")
            }
        }
    }

    func resizeBy(dx: CGFloat, dy: CGFloat) {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        var frame = panel.frame
        frame.size.width = max(panel.minSize.width, frame.width + dx)
        frame.size.height = max(panel.minSize.height, frame.height + dy)
        restoreFrame(frame, on: screen)
        saveFrame()
    }

    private func perform(_ action: GlobalHotkeyService.Action) {
        switch action {
        case .quick1: model?.requestQuickAction(slot: 1)
        case .quick2: model?.requestQuickAction(slot: 2)
        case .quick3: model?.requestQuickAction(slot: 3)
        case .quick4: model?.requestQuickAction(slot: 4)
        case .quick5: model?.requestQuickAction(slot: 5)
        case .toggle: toggle()
        case .clickThrough: toggleClickThrough()
        case .focus: focusInput()
        case .cancel: model?.stop()
        case .dim: preferences.opacity = max(0.35, preferences.opacity - 0.05); applyOpacity()
        case .brighten: preferences.opacity = min(1, preferences.opacity + 0.05); applyOpacity()
        case .left: moveBy(dx: -preferences.moveStep, dy: 0)
        case .right: moveBy(dx: preferences.moveStep, dy: 0)
        case .up: moveBy(dx: 0, dy: preferences.moveStep)
        case .down: moveBy(dx: 0, dy: -preferences.moveStep)
        case .narrower: resizeBy(dx: -preferences.resizeStep, dy: 0)
        case .wider: resizeBy(dx: preferences.resizeStep, dy: 0)
        case .shorter: resizeBy(dx: 0, dy: -preferences.resizeStep)
        case .taller: resizeBy(dx: 0, dy: preferences.resizeStep)
        case .screenshot:
            openMain(.screenshot)
            model?.screenshot.capturePrimaryDisplay(forRegion: false)
        case .regionScreenshot:
            openMain(.screenshot)
            model?.screenshot.capturePrimaryDisplay(forRegion: true)
        case .notes: toggleNotesPanel()
        case .sendWithScreenshot:
            guard model?.conversation.attachment != nil else {
                model?.notice = "Сначала приложите просмотренный снимок экрана."
                openMain(.screenshot)
                return
            }
            model?.send(includeScreenshot: true)
        case .sendWithoutScreenshot: model?.send(includeScreenshot: false)
        case .previousChat: model?.conversation.switchRelative(by: -1)
        case .nextChat: model?.conversation.switchRelative(by: 1)
        case .newChat: Task { await model?.conversation.createDefaultSubchat() }
        case .toggleChatList: isChatRailVisible.toggle()
        case .resetContext: model?.resetCurrentContext()
        case .toggleAudio: model?.toggleAudioFromShortcut()
        case .toggleAutomaticQuestions: model?.toggleAutomaticQuestionsFromShortcut()
        case .toggleLastSpeech: model?.toggleLastSpeechFromShortcut()
        case .toggleAutomaticSpeech: model?.toggleAutomaticSpeechFromShortcut()
        case .toggleTeleprompter: teleprompter.toggle()
        case .toggleTeleprompterClickThrough: teleprompter.toggleClickThrough()
        case .scrollUp: requestHistoryScroll(direction: -1)
        case .scrollDown: requestHistoryScroll(direction: 1)
        }
    }

    private func requestHistoryScroll(direction: Int) {
        historyScrollDirection = direction
        historyScrollRequest += 1
    }

    func moveBy(dx: CGFloat, dy: CGFloat) {
        guard let panel, isVisible else { return }
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX + dx, y: panel.frame.minY + dy))
        keepOnVisibleScreen()
        saveFrame()
    }

    func moveToNextScreen() {
        let screens = NSScreen.screens
        guard let panel, isVisible, screens.count > 1 else { return }
        let current = screens.firstIndex { $0 == panel.screen } ?? -1
        let target = screens[(current + 1) % screens.count]
        saveFrame()
        let area = target.visibleFrame
        let centered = NSRect(x: area.midX - panel.frame.width / 2,
                              y: area.midY - panel.frame.height / 2,
                              width: panel.frame.width, height: panel.frame.height)
        restoreFrame(preferences.savedFrame(for: target, minimumSize: panel.minSize) ?? centered,
                     on: target)
        preferences.save(frame: panel.frame, screen: target, minimumSize: panel.minSize)
    }

    private func restoreFrame(_ proposed: NSRect, on screen: NSScreen) {
        guard let panel else { return }
        guard let frame = OverlayPreferences.clampedFrame(proposed, to: screen.visibleFrame,
                                                          minimumSize: panel.minSize) else { return }
        isRestoringFrame = true
        panel.setFrame(frame, display: true)
        isRestoringFrame = false
    }

    private func keepOnVisibleScreen() {
        guard let panel else { return }
        let screens = NSScreen.screens
        let preferred = screens.firstIndex { $0 == panel.screen }
            ?? screens.firstIndex { $0 == NSScreen.main }
        guard let index = OverlayPreferences.targetScreenIndex(
            for: panel.frame, visibleFrames: screens.map(\.visibleFrame), preferredIndex: preferred
        ) else { return }
        restoreFrame(panel.frame, on: screens[index])
    }

    private func saveFrame() {
        guard !isRestoringFrame, let panel, let screen = panel.screen else { return }
        preferences.save(frame: panel.frame, screen: screen, minimumSize: panel.minSize)
    }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowWillClose(_ notification: Notification) { saveFrame(); isVisible = false }

    func shutdown() {
        teleprompter.shutdown()
        panel?.sharingType = .none
        compatibilityTask?.cancel()
        compatibilityTask = nil
        isCompatibilityMarkerVisible = false
        hide()
        hotkeys.stop()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel?.contentView = nil
        panel?.delegate = nil
        panel?.close()
        panel = nil
        model = nil
        openMainWindow = nil
    }
}
