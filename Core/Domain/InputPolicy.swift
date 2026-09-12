public enum PermissionState: Equatable, Sendable {
    case granted, notRequested, denied, restricted, unconfirmed
    public var title: String {
        switch self {
        case .granted: "Разрешено"
        case .notRequested: "Ещё не запрашивали"
        case .denied: "Доступ запрещён"
        case .restricted: "Ограничено системой"
        case .unconfirmed: "Доступ не подтверждён"
        }
    }
    public var canCapture: Bool { self == .granted }
}

public enum InputValidation {
    public static let maxDemoCharacters = 4_000
    public static func canSend(_ text: String) -> Bool {
        !text.allSatisfy(\.isWhitespace) && text.count <= maxDemoCharacters
    }
}
