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
    private let compatibilityTester: any OverlayCompatibilityTesting
    private weak var model: AppModel?
    var openMainWindow: (() -> Void)?
    private var panel: CopilotPanel?
    private var screenObserver: NSObjectProtocol?
    private var compatibilityTask: Task<Void, Never>?
    private var isRestoringFrame = false
    private(set) var isVisible = false
    private(set) var isClickThrough = false
    private(set) var focusRequest = 0
    private(set) var historyScrollRequest = 0
    private(set) var historyScrollDirection = 1
    private(set) var isChatRailVisible = true
    private(set) var compatibilityResult: OverlayCaptureCompatibility = .notTested
    private(set) var isCompatibilityMarkerVisible = false

    init(compatibilityTester: (any OverlayCompatibilityTesting)? = nil) {
        self.compatibilityTester = compatibilityTester ?? NativeOverlayCompatibilityTester()
    }

    func connect(model: AppModel) {
        self.model = model
        configureHotkeys()
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.keepOnVisibleScreen() }
        }
    }

    func configureHotkeys() {
        hotkeys.configure(enabled: preferences.shortcutsEnabled, preset: preferences.shortcutPreset,
                          overrides: preferences.hotkeyOverrides) { [weak self] in
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
            restoreFrame(preferences.savedFrame(for: screen) ?? defaultFrame, on: screen)
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

    func applyOpacity() {
        panel?.alphaValue = CGFloat(min(1, max(0.35, preferences.opacity)))
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
        panel.sharingType = .readOnly
        panel.displayIfNeeded()
        compatibilityTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                panel.sharingType = .none
                isCompatibilityMarkerVisible = false
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
        case .left: moveBy(dx: -24, dy: 0)
        case .right: moveBy(dx: 24, dy: 0)
        case .up: moveBy(dx: 0, dy: 24)
        case .down: moveBy(dx: 0, dy: -24)
        case .narrower: resizeBy(dx: -24, dy: 0)
        case .wider: resizeBy(dx: 24, dy: 0)
        case .shorter: resizeBy(dx: 0, dy: -24)
        case .taller: resizeBy(dx: 0, dy: 24)
        case .screenshot:
            openMain(.screenshot)
            model?.screenshot.capturePrimaryDisplay(forRegion: false)
        case .regionScreenshot:
            openMain(.screenshot)
            model?.screenshot.capturePrimaryDisplay(forRegion: true)
        case .notes: openMain(.notes)
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
        case .scrollUp: requestHistoryScroll(direction: -1)
        case .scrollDown: requestHistoryScroll(direction: 1)
        }
    }

    private func requestHistoryScroll(direction: Int) {
        historyScrollDirection = direction
        historyScrollRequest += 1
    }

    private func moveBy(dx: CGFloat, dy: CGFloat) {
        guard let panel, isVisible else { return }
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX + dx, y: panel.frame.minY + dy))
        keepOnVisibleScreen()
        saveFrame()
    }

    private func restoreFrame(_ proposed: NSRect, on screen: NSScreen) {
        guard let panel else { return }
        let area = screen.visibleFrame
        let width = min(max(panel.minSize.width, proposed.width), area.width)
        let height = min(max(panel.minSize.height, proposed.height), area.height)
        let frame = NSRect(x: min(max(area.minX, proposed.minX), area.maxX - width),
                           y: min(max(area.minY, proposed.minY), area.maxY - height), width: width, height: height)
        isRestoringFrame = true
        panel.setFrame(frame, display: true)
        isRestoringFrame = false
    }

    private func keepOnVisibleScreen() {
        guard let panel else { return }
        let target = NSScreen.screens.max { left, right in
            let a = left.visibleFrame.intersection(panel.frame)
            let b = right.visibleFrame.intersection(panel.frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }
        if let target { restoreFrame(panel.frame, on: target) }
    }

    private func saveFrame() {
        guard !isRestoringFrame, let panel, let screen = panel.screen else { return }
        preferences.save(frame: panel.frame, screen: screen)
    }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowWillClose(_ notification: Notification) { saveFrame(); isVisible = false }

    func shutdown() {
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
