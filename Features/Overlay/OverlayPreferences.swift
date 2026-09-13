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
    private(set) var hotkeyOverrides: [String: String] {
        didSet { defaults.set(hotkeyOverrides, forKey: "overlay.hotkeyOverrides") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedOpacity = defaults.object(forKey: "overlay.opacity") as? Double ?? 0.95
        opacity = storedOpacity.isFinite ? min(1, max(0.35, storedOpacity)) : 0.95
        shortcutPreset = ShortcutPreset(rawValue: defaults.string(forKey: "overlay.shortcutPreset") ?? "") ?? .commandOption
        shortcutsEnabled = defaults.object(forKey: "overlay.shortcutsEnabled") as? Bool ?? true
        hotkeyOverrides = defaults.dictionary(forKey: "overlay.hotkeyOverrides") as? [String: String] ?? [:]
    }

    func hotkeyOverride(for action: GlobalHotkeyService.Action) -> HotkeyOverride? {
        GlobalHotkeyService.decodeOverride(hotkeyOverrides[String(action.rawValue)])
    }

    func setHotkeyOverride(_ value: HotkeyOverride?, for action: GlobalHotkeyService.Action) {
        let key = String(action.rawValue)
        if let value { hotkeyOverrides[key] = GlobalHotkeyService.encodeOverride(value) }
        else { hotkeyOverrides.removeValue(forKey: key) }
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
    case commandOption, controlOption
    var id: String { rawValue }
    var title: String { self == .commandOption ? "⌘⌥ — Command + Option" : "⌃⌥ — Control + Option" }
    var symbols: String { self == .commandOption ? "⌘⌥" : "⌃⌥" }
}
