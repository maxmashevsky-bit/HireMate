public enum ProfileID: String, CaseIterable, Codable, Sendable, Identifiable {
    case liveCoding, technical, hr
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .liveCoding: "Go Live Coding"
        case .technical: "Go Техвопросы"
        case .hr: "Go HR"
        }
    }
    public var format: String {
        switch self {
        case .liveCoding:
            "Требования → уточнения → идея → инструменты → сложность → Go-код → крайние случаи → объяснение → оптимизация"
        case .technical:
            "Определение → механизм → пример Go/backend → компромиссы → типовые ошибки → итог"
        case .hr:
            "Ответ от первого лица только по подтверждённым фактам. STAR/PAR — когда уместно."
        }
    }
}

public struct DemoRequest: Sendable {
    public let profile: ProfileID
    public let question: String
    public init(profile: ProfileID, question: String) {
        self.profile = profile
        self.question = question
    }
}

public protocol LLMProvider: Sendable {
    func stream(_ request: DemoRequest) -> AsyncThrowingStream<String, Error>
}
