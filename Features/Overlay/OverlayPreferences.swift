import AppKit
import Observation

@MainActor @Observable
final class OverlayPreferences {
    private let defaults: UserDefaults
    var opacity: Double {
        didSet { defaults.set(min(1, max(0.35, opacity)), forKey: "overlay.opacity") }
    }
    var shortcutPreset: ShortcutPreset {
        didSet { defaults.set(shortcutPreset.rawValue, forKey: "overlay.shortcutPreset") }
    }
    var shortcutsEnabled: Bool {
        didSet { defaults.set(shortcutsEnabled, forKey: "overlay.shortcutsEnabled") }
    }
    var moveStep: Double {
        didSet { defaults.set(min(200, max(10, moveStep)), forKey: "overlay.moveStep") }
    }
    var resizeStep: Double {
        didSet { defaults.set(min(200, max(10, resizeStep)), forKey: "overlay.resizeStep") }
    }
    private(set) var hotkeyOverrides: [String: String] {
        didSet { defaults.set(hotkeyOverrides, forKey: "overlay.hotkeyOverrides") }
    }
    private(set) var disabledHotkeyActions: Set<String> {
        didSet { defaults.set(disabledHotkeyActions.sorted(), forKey: "overlay.disabledHotkeyActions") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedOpacity = defaults.object(forKey: "overlay.opacity") as? Double ?? 0.95
        opacity = storedOpacity.isFinite ? min(1, max(0.35, storedOpacity)) : 0.95
        shortcutPreset = ShortcutPreset(rawValue: defaults.string(forKey: "overlay.shortcutPreset") ?? "") ?? .command
        shortcutsEnabled = defaults.object(forKey: "overlay.shortcutsEnabled") as? Bool ?? true
        let storedMoveStep = defaults.object(forKey: "overlay.moveStep") as? Double ?? 50
        moveStep = storedMoveStep.isFinite ? min(200, max(10, storedMoveStep)) : 50
        let storedResizeStep = defaults.object(forKey: "overlay.resizeStep") as? Double ?? 50
        resizeStep = storedResizeStep.isFinite ? min(200, max(10, storedResizeStep)) : 50
        hotkeyOverrides = defaults.dictionary(forKey: "overlay.hotkeyOverrides") as? [String: String] ?? [:]
        disabledHotkeyActions = Set(defaults.stringArray(forKey: "overlay.disabledHotkeyActions") ?? [])
    }

    func hotkeyOverride(for action: GlobalHotkeyService.Action) -> HotkeyOverride? {
        GlobalHotkeyService.decodeOverride(hotkeyOverrides[String(action.rawValue)])
    }

    func restoreInputHint(focusShortcutRegistered: Bool) -> String {
        if shortcutsEnabled, focusShortcutRegistered {
            return "Вернуть ввод: \(shortcutLabel(for: .focus))"
        }
        return "В меню приложения выберите «Вернуть ввод в окне подсказок»."
    }

    func shortcutLabel(for action: GlobalHotkeyService.Action) -> String {
        guard isHotkeyEnabled(action) else { return "Отключено" }
        let custom = hotkeyOverride(for: action)
        let alternate = action.needsAlternateBase
            ? (shortcutPreset == .commandOption ? "⌃" : "⌘") : ""
        return shortcutPreset.symbols + alternate
            + ((custom?.usesShift ?? action.needsShift) ? "⇧" : "")
            + (custom?.key ?? action.defaultKey).title
    }

    func setHotkeyOverride(_ value: HotkeyOverride?, for action: GlobalHotkeyService.Action) {
        let key = String(action.rawValue)
        if let value { hotkeyOverrides[key] = GlobalHotkeyService.encodeOverride(value) }
        else { hotkeyOverrides.removeValue(forKey: key) }
    }

    func isHotkeyEnabled(_ action: GlobalHotkeyService.Action) -> Bool {
        !disabledHotkeyActions.contains(String(action.rawValue))
    }

    func setHotkeyEnabled(_ enabled: Bool, for action: GlobalHotkeyService.Action) {
        let key = String(action.rawValue)
        if enabled { disabledHotkeyActions.remove(key) }
        else { disabledHotkeyActions.insert(key) }
    }

    func resetAllHotkeys() {
        shortcutPreset = .command
        hotkeyOverrides.removeAll()
        disabledHotkeyActions.removeAll()
    }

    func savedFrame(for screen: NSScreen, minimumSize: NSSize = NSSize(width: 640, height: 500)) -> NSRect? {
        let frames = defaults.dictionary(forKey: "overlay.frames") as? [String: String] ?? [:]
        guard let value = frames[screenKey(screen)] else { return nil }
        return Self.clampedFrame(NSRectFromString(value), to: screen.visibleFrame, minimumSize: minimumSize)
    }

    func save(frame: NSRect, screen: NSScreen, minimumSize: NSSize = NSSize(width: 640, height: 500)) {
        guard let frame = Self.clampedFrame(frame, to: screen.visibleFrame, minimumSize: minimumSize) else { return }
        var frames = defaults.dictionary(forKey: "overlay.frames") as? [String: String] ?? [:]
        frames[screenKey(screen)] = NSStringFromRect(frame)
        defaults.set(frames, forKey: "overlay.frames")
    }

    static func targetScreenIndex(for frame: NSRect, visibleFrames: [NSRect],
                                  preferredIndex: Int?) -> Int? {
        guard !visibleFrames.isEmpty else { return nil }
        let fallback = preferredIndex.flatMap { visibleFrames.indices.contains($0) ? $0 : nil } ?? 0
        var selected = fallback
        var largestArea: CGFloat = 0
        for index in [fallback] + visibleFrames.indices.filter({ $0 != fallback }) {
            let intersection = visibleFrames[index].intersection(frame)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            if area.isFinite, area > largestArea {
                selected = index
                largestArea = area
            }
        }
        return selected
    }

    static func clampedFrame(_ proposed: NSRect, to visibleFrame: NSRect,
                             minimumSize: NSSize) -> NSRect? {
        let values = [proposed.minX, proposed.minY, proposed.width, proposed.height,
                      visibleFrame.minX, visibleFrame.minY, visibleFrame.width, visibleFrame.height,
                      minimumSize.width, minimumSize.height]
        guard values.allSatisfy(\.isFinite), visibleFrame.width > 0, visibleFrame.height > 0 else { return nil }
        let minimumWidth = min(max(1, minimumSize.width), visibleFrame.width)
        let minimumHeight = min(max(1, minimumSize.height), visibleFrame.height)
        let width = min(max(minimumWidth, proposed.width), visibleFrame.width)
        let height = min(max(minimumHeight, proposed.height), visibleFrame.height)
        let x = min(max(visibleFrame.minX, proposed.minX), visibleFrame.maxX - width)
        let y = min(max(visibleFrame.minY, proposed.minY), visibleFrame.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func screenKey(_ screen: NSScreen) -> String {
        // Только локальный номер дисплея; серийный номер/EDID не читаются.
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.stringValue ?? "default"
    }
}

enum ShortcutPreset: String, CaseIterable, Identifiable {
    case command, commandOption, controlOption
    var id: String { rawValue }
    var title: String {
        switch self {
        case .command: "⌘ — Command"
        case .commandOption: "⌘⌥ — Command + Option"
        case .controlOption: "⌃⌥ — Control + Option"
        }
    }
    var symbols: String {
        switch self {
        case .command: "⌘"
        case .commandOption: "⌘⌥"
        case .controlOption: "⌃⌥"
        }
    }
}
