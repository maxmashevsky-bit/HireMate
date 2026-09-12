/// Детерминированный preview, не модель и не оценка вопроса пользователя.
public struct FakeLLMProvider: LLMProvider {
    public let delayNanoseconds: UInt64
    public init(delayNanoseconds: UInt64 = 35_000_000) { self.delayNanoseconds = delayNanoseconds }

    public func stream(_ request: DemoRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    guard InputValidation.canSend(request.question) else {
                        throw DemoError.invalidInput
                    }
                    for word in Self.sample(for: request.profile).split(separator: " ", omittingEmptySubsequences: false) {
                        try Task.checkCancellation()
                        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
                        continuation.yield(String(word) + " ")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }

    public static func sample(for profile: ProfileID) -> String {
        let prefix = "Демонстрационный образец. Вопрос не анализируется; AI и сеть не используются.\n\n"
        switch profile {
        case .liveCoding:
            return prefix + "1. Требования: учебный пример — сумма элементов []int.\n2. Уточнения: допустим ли пустой список и переполнение int?\n3. Идея: пройти массив один раз.\n4. Инструменты: цикл range, аккумулятор int.\n5. Сложность: O(n) времени, O(1) памяти.\n6. Код Go:\n```go\nfunc sum(values []int) int {\n    total := 0\n    for _, value := range values {\n        total += value\n    }\n    return total\n}\n```\n7. Крайние случаи: nil, пустой список, отрицательные числа; переполнение требует отдельного условия.\n8. Объяснение: каждый элемент прибавляется ровно один раз.\n9. Оптимизация: асимптотически быстрее прочитать произвольный массив нельзя."
        case .technical:
            return prefix + "Определение: транзакция объединяет операции с данными.\nМеханизм: BEGIN начинает, COMMIT фиксирует, ROLLBACK отменяет.\nПример Go/backend: списание и зачисление выполняются в одной SQL-транзакции через database/sql.\nКомпромиссы: более строгая изоляция уменьшает аномалии, но может увеличить ожидания и число повторов.\nТиповые ошибки: забыть rollback, держать транзакцию во время долгого внешнего запроса.\nИтог: сначала определите инвариант, затем границы транзакции и уровень изоляции."
        case .hr:
            return prefix + "Для ответа от первого лица нужны подтверждённые факты. Сейчас они не добавлены.\n\nКаркас собственного ответа:\n«В проекте [название] я отвечал за [подтверждённую задачу]. Я сделал [действие]. Результат — [проверяемый факт].»\n\nЗаполните пропуски своими сведениями. Название Rapid, стаж, технологии и метрики автоматически не приписываются вам."
        }
    }
}

public enum DemoError: Error {
    case invalidInput
    public var errorDescription: String? { "Введите вопрос длиной от 1 до 4 000 символов." }
}
