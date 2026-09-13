import Carbon
import Observation

enum HotkeyKey: String, CaseIterable, Identifiable {
    case b, w, d, g, h, n, k, l, p, x, r, a
    case one, two, three, four, five
    case leftBracket, rightBracket, `return`
    case left, right, up, down

    var id: String { rawValue }
    var title: String {
        switch self {
        case .leftBracket: "["
        case .rightBracket: "]"
        case .return: "Return"
        case .left: "←"
        case .right: "→"
        case .up: "↑"
        case .down: "↓"
        default: rawValue.uppercased()
        }
    }
    var keyCode: UInt32 {
        switch self {
        case .b: UInt32(kVK_ANSI_B)
        case .w: UInt32(kVK_ANSI_W)
        case .d: UInt32(kVK_ANSI_D)
        case .g: UInt32(kVK_ANSI_G)
        case .h: UInt32(kVK_ANSI_H)
        case .n: UInt32(kVK_ANSI_N)
        case .k: UInt32(kVK_ANSI_K)
        case .l: UInt32(kVK_ANSI_L)
        case .p: UInt32(kVK_ANSI_P)
        case .x: UInt32(kVK_ANSI_X)
        case .r: UInt32(kVK_ANSI_R)
        case .a: UInt32(kVK_ANSI_A)
        case .one: UInt32(kVK_ANSI_1)
        case .two: UInt32(kVK_ANSI_2)
        case .three: UInt32(kVK_ANSI_3)
        case .four: UInt32(kVK_ANSI_4)
        case .five: UInt32(kVK_ANSI_5)
        case .leftBracket: UInt32(kVK_ANSI_LeftBracket)
        case .rightBracket: UInt32(kVK_ANSI_RightBracket)
        case .return: UInt32(kVK_Return)
        case .left: UInt32(kVK_LeftArrow)
        case .right: UInt32(kVK_RightArrow)
        case .up: UInt32(kVK_UpArrow)
        case .down: UInt32(kVK_DownArrow)
        }
    }
}

struct HotkeyOverride: Equatable {
    let key: HotkeyKey
    let usesShift: Bool
}

@MainActor @Observable
final class GlobalHotkeyService {
    enum Action: UInt32, CaseIterable {
        case toggle = 1, clickThrough, focus, cancel, dim, brighten
        case left, right, up, down, narrower, wider, shorter, taller
        case quick1, quick2, quick3, quick4, quick5
        case screenshot, regionScreenshot, notes
        case sendWithScreenshot, sendWithoutScreenshot
        case previousChat, nextChat, newChat, toggleChatList, resetContext
        case toggleAudio, toggleAutomaticQuestions, scrollUp, scrollDown
        var defaultKey: HotkeyKey {
            switch self {
            case .quick1: .one
            case .quick2: .two
            case .quick3: .three
            case .quick4: .four
            case .quick5: .five
            case .toggle: .b
            case .clickThrough: .w
            case .focus: .d
            case .cancel: .g
            case .dim: .leftBracket
            case .brighten: .rightBracket
            case .left, .narrower: .left
            case .right, .wider: .right
            case .up, .taller, .scrollUp: .up
            case .down, .shorter, .scrollDown: .down
            case .screenshot, .regionScreenshot: .h
            case .notes: .n
            case .sendWithScreenshot, .sendWithoutScreenshot: .return
            case .previousChat: .k
            case .nextChat: .l
            case .newChat, .toggleChatList: .p
            case .resetContext: .x
            case .toggleAudio: .r
            case .toggleAutomaticQuestions: .a
            }
        }
        var needsShift: Bool {
            [.narrower, .wider, .shorter, .taller, .regionScreenshot, .sendWithoutScreenshot,
             .previousChat, .nextChat, .toggleChatList, .resetContext, .toggleAutomaticQuestions].contains(self)
        }
        var needsAlternateBase: Bool { [.scrollUp, .scrollDown].contains(self) }
        var title: String {
            switch self {
            case .quick1: "Быстрое действие 1"
            case .quick2: "Быстрое действие 2"
            case .quick3: "Быстрое действие 3"
            case .quick4: "Быстрое действие 4"
            case .quick5: "Быстрое действие 5"
            case .toggle: "Показать / скрыть"
            case .clickThrough: "Пропускать клики"
            case .focus: "Ввод вопроса"
            case .cancel: "Остановить ответ"
            case .dim: "Меньше непрозрачность"
            case .brighten: "Больше непрозрачность"
            case .left, .right, .up, .down: "Перемещение окна"
            case .narrower, .wider, .shorter, .taller: "Изменение размера"
            case .screenshot: "Снимок экрана"
            case .regionScreenshot: "Снимок области"
            case .notes: "Заметки"
            case .sendWithScreenshot: "Отправить со снимком"
            case .sendWithoutScreenshot: "Отправить без снимка"
            case .previousChat: "Предыдущий поддиалог"
            case .nextChat: "Следующий поддиалог"
            case .newChat: "Новый поддиалог"
            case .toggleChatList: "Список поддиалогов"
            case .resetContext: "Сбросить текущий контекст"
            case .toggleAudio: "Захват звука"
            case .toggleAutomaticQuestions: "Автоматические вопросы"
            case .scrollUp, .scrollDown: "Прокрутка ответа"
            }
        }
    }

    private static weak var active: GlobalHotkeyService?
    private var handler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private var actionHandler: ((Action) -> Void)?
    private(set) var issues: [String] = []
    private(set) var registeredCount = 0

    func configure(enabled: Bool, preset: ShortcutPreset, overrides: [String: String],
                   onAction: @escaping (Action) -> Void) {
        stop()
        issues = []
        guard enabled else { return }
        actionHandler = onAction
        Self.active = self
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x4D49434F else { return OSStatus(eventNotHandledErr) }
            // Application event target обрабатывается главным event loop AppKit.
            return MainActor.assumeIsolated {
                guard !IsSecureEventInputEnabled(),
                      let action = Action(rawValue: identifier.id),
                      let service = GlobalHotkeyService.active else { return OSStatus(eventNotHandledErr) }
                service.actionHandler?(action)
                return noErr
            }
        }, 1, &eventType, nil, &handler)
        guard status == noErr else {
            issues = ["Глобальные сочетания недоступны (код \(status)). Используйте меню приложения."]
            stop()
            return
        }
        for action in Action.allCases {
            var reference: EventHotKeyRef?
            let custom = Self.decodeOverride(overrides[String(action.rawValue)])
            let key = custom?.key ?? action.defaultKey
            var modifiers = preset == .commandOption ? UInt32(cmdKey | optionKey) : UInt32(controlKey | optionKey)
            if custom?.usesShift ?? action.needsShift { modifiers |= UInt32(shiftKey) }
            if action.needsAlternateBase {
                modifiers |= preset == .commandOption ? UInt32(controlKey) : UInt32(cmdKey)
            }
            let identifier = EventHotKeyID(signature: 0x4D49434F, id: action.rawValue)
            let result = RegisterEventHotKey(key.keyCode, modifiers, identifier,
                                             GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference {
                registrations.append(reference)
            } else {
                issues.append("«\(action.title)»: сочетание не зарегистрировано (код \(result)). Выберите другой набор.")
            }
        }
        registeredCount = registrations.count
    }

    static func encodeOverride(_ value: HotkeyOverride) -> String {
        "\(value.key.rawValue)|\(value.usesShift ? 1 : 0)"
    }

    static func decodeOverride(_ value: String?) -> HotkeyOverride? {
        guard let parts = value?.split(separator: "|", omittingEmptySubsequences: false), parts.count == 2,
              let key = HotkeyKey(rawValue: String(parts[0])), ["0", "1"].contains(parts[1]) else { return nil }
        return HotkeyOverride(key: key, usesShift: parts[1] == "1")
    }

    func stop() {
        for reference in registrations { UnregisterEventHotKey(reference) }
        registrations.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        actionHandler = nil
        registeredCount = 0
        if Self.active === self { Self.active = nil }
    }
}
