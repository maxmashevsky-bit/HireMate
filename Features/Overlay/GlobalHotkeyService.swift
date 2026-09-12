import Carbon
import Observation

@MainActor @Observable
final class GlobalHotkeyService {
    enum Action: UInt32, CaseIterable {
        case toggle = 1, clickThrough, focus, cancel, dim, brighten
        case left, right, up, down, narrower, wider, shorter, taller
        case quick1, quick2, quick3, quick4, quick5
        var keyCode: UInt32 {
            switch self {
            case .quick1: UInt32(kVK_ANSI_1)
            case .quick2: UInt32(kVK_ANSI_2)
            case .quick3: UInt32(kVK_ANSI_3)
            case .quick4: UInt32(kVK_ANSI_4)
            case .quick5: UInt32(kVK_ANSI_5)
            case .toggle: UInt32(kVK_ANSI_B)
            case .clickThrough: UInt32(kVK_ANSI_W)
            case .focus: UInt32(kVK_ANSI_D)
            case .cancel: UInt32(kVK_ANSI_G)
            case .dim: UInt32(kVK_ANSI_LeftBracket)
            case .brighten: UInt32(kVK_ANSI_RightBracket)
            case .left, .narrower: UInt32(kVK_LeftArrow)
            case .right, .wider: UInt32(kVK_RightArrow)
            case .up, .taller: UInt32(kVK_UpArrow)
            case .down, .shorter: UInt32(kVK_DownArrow)
            }
        }
        var needsShift: Bool { [.narrower, .wider, .shorter, .taller].contains(self) }
        var title: String {
            switch self {
            case .quick1, .quick2, .quick3, .quick4, .quick5: "Быстрое действие"
            case .toggle: "Показать / скрыть"
            case .clickThrough: "Пропускать клики"
            case .focus: "Ввод вопроса"
            case .cancel: "Остановить ответ"
            case .dim: "Меньше непрозрачность"
            case .brighten: "Больше непрозрачность"
            case .left, .right, .up, .down: "Перемещение окна"
            case .narrower, .wider, .shorter, .taller: "Изменение размера"
            }
        }
    }

    private static weak var active: GlobalHotkeyService?
    private var handler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private var actionHandler: ((Action) -> Void)?
    private(set) var issues: [String] = []
    private(set) var registeredCount = 0

    func configure(enabled: Bool, preset: ShortcutPreset, onAction: @escaping (Action) -> Void) {
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
            var modifiers = preset == .commandOption ? UInt32(cmdKey | optionKey) : UInt32(controlKey | optionKey)
            if action.needsShift { modifiers |= UInt32(shiftKey) }
            let identifier = EventHotKeyID(signature: 0x4D49434F, id: action.rawValue)
            let result = RegisterEventHotKey(action.keyCode, modifiers, identifier,
                                             GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference {
                registrations.append(reference)
            } else {
                issues.append("«\(action.title)»: сочетание не зарегистрировано (код \(result)). Выберите другой набор.")
            }
        }
        registeredCount = registrations.count
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
