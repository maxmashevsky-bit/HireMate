import AppKit
import Observation
import CopilotCore

enum OverlayStatusCorner: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    var isTop: Bool { self == .topLeft || self == .topRight }
    var isLeading: Bool { self == .topLeft || self == .bottomLeft }
    var title: String {
        switch self {
        case .topLeft: "Слева сверху"
        case .topRight: "Справа сверху"
        case .bottomLeft: "Слева снизу"
        case .bottomRight: "Справа снизу"
        }
    }
}

@MainActor @Observable
final class TeleprompterAppearance {
    private let defaults: UserDefaults
    var background: AppAccent { didSet { defaults.set(background.hex, forKey: "teleprompter.backgroundColor") } }
    var neighbor: AppAccent { didSet { defaults.set(neighbor.hex, forKey: "teleprompter.neighborColor") } }
    var active: AppAccent { didSet { defaults.set(active.hex, forKey: "teleprompter.activeColor") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        background = defaults.string(forKey: "teleprompter.backgroundColor").flatMap(AppAccent.init(hex:)) ?? AppAccent(rgb: 0x111111)
        neighbor = defaults.string(forKey: "teleprompter.neighborColor").flatMap(AppAccent.init(hex:)) ?? AppAccent(rgb: 0xFFFFFF)
        active = defaults.string(forKey: "teleprompter.activeColor").flatMap(AppAccent.init(hex:)) ?? AppAccent(rgb: 0xFFFFFF)
    }

    func reset() {
        background = AppAccent(rgb: 0x111111)
        neighbor = AppAccent(rgb: 0xFFFFFF)
        active = AppAccent(rgb: 0xFFFFFF)
    }
}

@MainActor @Observable
final class OverlayPreferences {
    private let defaults: UserDefaults
    var showsStatusIndicator: Bool {
        didSet { defaults.set(showsStatusIndicator, forKey: "overlay.showsStatusIndicator") }
    }
    var statusCorner: OverlayStatusCorner {
        didSet { defaults.set(statusCorner.rawValue, forKey: "overlay.statusCorner") }
    }
    var opacity: Double {
        didSet { defaults.set(min(1, max(0.35, opacity)), forKey: "overlay.opacity") }
    }
    var shortcutPreset: ShortcutPreset {
        didSet { defaults.set(shortcutPreset.rawValue, forKey: "overlay.shortcutPreset") }
    }
    var shortcutsEnabled: Bool {
        didSet { defaults.set(shortcutsEnabled, forKey: "overlay.shortcutsEnabled") }
    }
    var smartAutoScroll: Bool {
        didSet { defaults.set(smartAutoScroll, forKey: "overlay.smartAutoScroll") }
    }
    private var storedAutoScrollSpeed: Double
    var autoScrollSpeed: Double {
        get { storedAutoScrollSpeed }
        set {
            storedAutoScrollSpeed = Self.normalizedScrollSpeed(newValue)
            defaults.set(storedAutoScrollSpeed, forKey: "overlay.autoScrollSpeed")
        }
    }
    var autoScrollAnimationDuration: Double { 0.18 / storedAutoScrollSpeed }
    private static func normalizedScrollSpeed(_ value: Double) -> Double {
        value.isFinite ? min(2, max(0.25, value)) : 1
    }
    var showsQuickActions: Bool {
        didSet { defaults.set(showsQuickActions, forKey: "overlay.showsQuickActions") }
    }
    var compactQuickActions: Bool {
        didSet { defaults.set(compactQuickActions, forKey: "overlay.compactQuickActions") }
    }
    private(set) var panelLayout: MeetingPanelLayout {
        didSet {
            if let data = try? JSONEncoder().encode(panelLayout) {
                defaults.set(data, forKey: "overlay.panelLayout.v1")
            }
        }
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
        showsStatusIndicator = defaults.object(forKey: "overlay.showsStatusIndicator") as? Bool ?? true
        statusCorner = OverlayStatusCorner(rawValue: defaults.string(forKey: "overlay.statusCorner") ?? "") ?? .bottomRight
        let storedOpacity = defaults.object(forKey: "overlay.opacity") as? Double ?? 0.95
        opacity = storedOpacity.isFinite ? min(1, max(0.35, storedOpacity)) : 0.95
        shortcutPreset = ShortcutPreset(rawValue: defaults.string(forKey: "overlay.shortcutPreset") ?? "") ?? .command
        shortcutsEnabled = defaults.object(forKey: "overlay.shortcutsEnabled") as? Bool ?? true
        smartAutoScroll = defaults.object(forKey: "overlay.smartAutoScroll") as? Bool ?? true
        storedAutoScrollSpeed = Self.normalizedScrollSpeed(defaults.object(forKey: "overlay.autoScrollSpeed") as? Double ?? 1)
        showsQuickActions = defaults.object(forKey: "overlay.showsQuickActions") as? Bool ?? true
        compactQuickActions = defaults.object(forKey: "overlay.compactQuickActions") as? Bool ?? false
        panelLayout = MeetingPanelLayout.restore(defaults.data(forKey: "overlay.panelLayout.v1"))
        let storedMoveStep = defaults.object(forKey: "overlay.moveStep") as? Double ?? 50
        moveStep = storedMoveStep.isFinite ? min(200, max(10, storedMoveStep)) : 50
        let storedResizeStep = defaults.object(forKey: "overlay.resizeStep") as? Double ?? 50
        resizeStep = storedResizeStep.isFinite ? min(200, max(10, storedResizeStep)) : 50
        hotkeyOverrides = defaults.dictionary(forKey: "overlay.hotkeyOverrides") as? [String: String] ?? [:]
        disabledHotkeyActions = Set(defaults.stringArray(forKey: "overlay.disabledHotkeyActions") ?? [])
        // Новая команда не перехватывает сочетание до явного включения в редакторе.
        if defaults.object(forKey: "overlay.modelCycleShortcutConfigured") as? Bool != true {
            disabledHotkeyActions.insert(String(GlobalHotkeyService.Action.cycleModels.rawValue))
        }
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

    func quickActionShortcutLabel(slot: Int) -> String {
        guard shortcutsEnabled else { return "Горячие клавиши отключены" }
        let actions: [GlobalHotkeyService.Action] = [.quick1, .quick2, .quick3, .quick4, .quick5]
        guard (1...actions.count).contains(slot) else { return "Не назначено" }
        return shortcutLabel(for: actions[slot - 1])
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
        if action == .cycleModels { defaults.set(true, forKey: "overlay.modelCycleShortcutConfigured") }
        let key = String(action.rawValue)
        if enabled { disabledHotkeyActions.remove(key) }
        else { disabledHotkeyActions.insert(key) }
    }

    func resetAllHotkeys() {
        shortcutPreset = .command
        hotkeyOverrides.removeAll()
        disabledHotkeyActions.removeAll()
        disabledHotkeyActions.insert(String(GlobalHotkeyService.Action.cycleModels.rawValue))
    }

    func movePanelTool(_ tool: MeetingPanelTool, to zone: MeetingPanelZone, before target: MeetingPanelTool? = nil) {
        panelLayout.move(tool, to: zone, before: target)
    }

    func resetPanelLayout() {
        panelLayout = .standard
        showsQuickActions = true
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

enum MeetingPanelZone: String, CaseIterable, Identifiable, Sendable {
    case header, input, hidden
    var id: String { rawValue }
    var title: String {
        switch self {
        case .header: "Верхняя панель"
        case .input: "Область ввода"
        case .hidden: "Скрытые элементы"
        }
    }
}

enum MeetingPanelTool: String, Codable, CaseIterable, Identifiable, Sendable {
    case audio, provider, appearance, headerNotes, headerTeleprompter, home
    case context, screenshot, transcription, inputNotes, inputTeleprompter, stop, send, speech
    var id: String { rawValue }
    var title: String {
        switch self {
        case .audio: "Микрофон"
        case .provider: "Модель ответа"
        case .appearance: "Управление окном"
        case .headerNotes, .inputNotes: "Заметки"
        case .headerTeleprompter, .inputTeleprompter: "Телесуфлёр"
        case .home: "Главное окно"
        case .context: "Контекст"
        case .screenshot: "Снимок экрана"
        case .transcription: "Расшифровка"
        case .stop: "Остановить ответ"
        case .send: "Отправить вопрос"
        case .speech: "Озвучить ответ"
        }
    }
    var icon: String {
        switch self {
        case .audio: "mic"
        case .provider: "cpu"
        case .appearance: "slider.horizontal.3"
        case .headerNotes, .inputNotes: "note.text"
        case .headerTeleprompter, .inputTeleprompter: "text.viewfinder"
        case .home: "house"
        case .context: "person.text.rectangle"
        case .screenshot: "camera"
        case .transcription: "text.bubble"
        case .stop: "stop.fill"
        case .send: "arrow.up.circle.fill"
        case .speech: "speaker.wave.2"
        }
    }
}

struct MeetingPanelLayout: Codable, Equatable, Sendable {
    private(set) var header: [MeetingPanelTool]
    private(set) var input: [MeetingPanelTool]
    private(set) var hidden: [MeetingPanelTool]

    static let standard = MeetingPanelLayout(
        header: [.audio, .provider, .appearance, .headerNotes, .headerTeleprompter, .home],
        input: [.context, .screenshot, .transcription, .inputNotes, .inputTeleprompter, .stop, .send, .speech], hidden: [])

    static func restore(_ data: Data?) -> Self {
        guard let data, let layout = try? JSONDecoder().decode(Self.self, from: data) else { return .standard }
        let all = layout.header + layout.input + layout.hidden
        guard all.count == MeetingPanelTool.allCases.count, Set(all) == Set(MeetingPanelTool.allCases) else { return .standard }
        return layout
    }

    subscript(zone: MeetingPanelZone) -> [MeetingPanelTool] {
        get {
            switch zone {
            case .header: header
            case .input: input
            case .hidden: hidden
            }
        }
        set {
            switch zone {
            case .header: header = newValue
            case .input: input = newValue
            case .hidden: hidden = newValue
            }
        }
    }

    mutating func move(_ tool: MeetingPanelTool, to zone: MeetingPanelZone, before target: MeetingPanelTool? = nil) {
        guard target != tool else { return }
        for existingZone in MeetingPanelZone.allCases { self[existingZone].removeAll { $0 == tool } }
        let index = target.flatMap { self[zone].firstIndex(of: $0) } ?? self[zone].endIndex
        self[zone].insert(tool, at: index)
    }
}

struct HistoryViewport: Equatable {
    var offset: CGFloat = 0
    var height: CGFloat = 0
    var contentHeight: CGFloat = 0

    var maximumOffset: CGFloat { max(0, contentHeight - height) }
    var nearBottom: Bool { offset >= maximumOffset - 48 }
    func nearLatest(order: MessageOrder) -> Bool {
        maximumOffset == 0 || (order == .newestTop ? offset <= 48 : nearBottom)
    }

    func pagedOffset(direction: Int) -> CGFloat {
        guard height > 0, direction != 0 else { return offset }
        let step = max(40, height * 0.8)
        return min(maximumOffset, max(0, offset + (direction < 0 ? -step : step)))
    }
}

struct HistoryScrollPolicy: Equatable {
    private(set) var followsLatest = true
    private(set) var hasUnreadContent = false

    mutating func beginUserScroll() { followsLatest = false }

    mutating func endUserScroll(nearLatest: Bool) {
        followsLatest = nearLatest
        if nearLatest { hasUnreadContent = false }
    }

    mutating func receivedContent(automatically: Bool) -> Bool {
        guard automatically, followsLatest else {
            hasUnreadContent = true
            return false
        }
        hasUnreadContent = false
        return true
    }

    mutating func jumpToLatest() {
        followsLatest = true
        hasUnreadContent = false
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
