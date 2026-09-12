import Foundation

public struct QuickAction: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var slot: Int
    public var name: String
    public var profileID: ProfileID
    public var prompt: String
    public var includeScreenshot = false
    public var selectedModel = ""
    public var outputStyle = "Кратко, с объяснением"
    public var requiresConfirmation = true
    public init(slot: Int, name: String, profileID: ProfileID, prompt: String) {
        id = UUID(); self.slot = slot; self.name = name; self.profileID = profileID; self.prompt = prompt
    }
    public var isValid: Bool {
        (1...5).contains(slot) && (1...15).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count)
            && (1...4_000).contains(prompt.trimmingCharacters(in: .whitespacesAndNewlines).count)
            && outputStyle.count <= 500 && selectedModel.count <= 256
            && !selectedModel.contains("\n") && !selectedModel.contains("\r")
    }
    public static var defaults: [QuickAction] {
        [QuickAction(slot: 1, name: "Разбор задачи", profileID: .liveCoding, prompt: "Разбери условие: что требуется, какие есть ограничения и уточнения. Предложи план решения на Go и оцени сложность."),
         QuickAction(slot: 2, name: "Проверить код", profileID: .liveCoding, prompt: "Проверь предоставленный код Go: ошибки, гонки, утечки, крайние случаи. Объясни причины и предложи минимальные исправления. Не утверждай, что запускал код."),
         QuickAction(slot: 3, name: "Оптимизация", profileID: .liveCoding, prompt: "Оцени время и память решения. Предложи оптимизацию и объясни компромиссы без выдуманных результатов измерений."),
         QuickAction(slot: 4, name: "Техвопрос", profileID: .technical, prompt: "Дай структурированный ответ на технический вопрос: определение, механизм, пример в Go/backend, компромиссы и типичные ошибки."),
         QuickAction(slot: 5, name: "Мой опыт", profileID: .hr, prompt: "Помоги сформулировать ответ от первого лица только по подтверждённым фактам активного профиля. Не добавляй стаж, проекты, технологии и метрики, которых в фактах нет. При нехватке данных предложи уточнения.")]
    }
}
