import AppKit
import SwiftUI
import Observation

@MainActor
private final class CopilotPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}

@MainActor @Observable
final class OverlayController: NSObject, NSWindowDelegate {
    let preferences = OverlayPreferences()
    let hotkeys = GlobalHotkeyService()
    private weak var model: AppModel?
    var openMainWindow: (() -> Void)?
    private var panel: CopilotPanel?
    private var screenObserver: NSObjectProtocol?
    private var isRestoringFrame = false
    private(set) var isVisible = false
    private(set) var isClickThrough = false
    private(set) var focusRequest = 0

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
        hotkeys.configure(enabled: preferences.shortcutsEnabled, preset: preferences.shortcutPreset) { [weak self] in
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
        }
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
