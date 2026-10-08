import Foundation

public struct StageDurationStatistic: Equatable, Sendable, Identifiable {
    public let stageID: UUID
    public let completedCount: Int
    public let averageSeconds: TimeInterval?
    public var id: UUID { stageID }
}

public enum TrackerStatistics {
    /// Только завершённые пребывания: от создания/входа до следующего подтверждённого выхода.
    /// Текущий этап, разорванные цепочки и некорректные даты не превращаются в оценку.
    public static func stageDurations(stages: [VacancyStage], vacancies: [Vacancy], transitions: [VacancyTransition]) -> [StageDurationStatistic] {
        let history = Dictionary(grouping: transitions, by: \.vacancyID)
        var durations: [UUID: (count: Int, mean: TimeInterval)] = [:]
        var seenVacancies: Set<UUID> = []
        for vacancy in vacancies where seenVacancies.insert(vacancy.id).inserted {
            guard vacancy.createdAt.timeIntervalSince1970.isFinite else { continue }
            let events = (history[vacancy.id] ?? []).filter { $0.happenedAt.timeIntervalSince1970.isFinite }.sorted {
                $0.happenedAt == $1.happenedAt ? $0.id.uuidString < $1.id.uuidString : $0.happenedAt < $1.happenedAt
            }
            var stage: UUID?
            var enteredAt = vacancy.createdAt
            var seen: Set<UUID> = []
            for event in events where seen.insert(event.id).inserted {
                guard event.happenedAt >= enteredAt else { continue }
                if event.fromStageID == nil {
                    guard stage == nil else { continue }
                    stage = event.toStageID; enteredAt = event.happenedAt; continue
                }
                guard let from = event.fromStageID, from != event.toStageID else { continue }
                if stage == nil { stage = from }
                guard stage == from else { continue }
                let duration = event.happenedAt.timeIntervalSince(enteredAt)
                guard duration.isFinite, duration >= 0 else { continue }
                let previous = durations[from] ?? (count: 0, mean: 0)
                let count = previous.count + 1
                durations[from] = (count, previous.mean + (duration - previous.mean) / Double(count))
                stage = event.toStageID; enteredAt = event.happenedAt
            }
        }
        return stages.map { stage in
            let value = durations[stage.id]
            return StageDurationStatistic(stageID: stage.id, completedCount: value?.count ?? 0, averageSeconds: value?.mean)
        }
    }
}

public enum OfferComparison {
    public static func eligible(_ vacancies: [Vacancy], stageIDs: Set<UUID>? = nil) -> [Vacancy] {
        vacancies.filter { !$0.isArchived && $0.isValid && $0.hasComparisonData && (stageIDs?.contains($0.stageID) ?? true) }
    }
    public static func pair(firstID: UUID?, secondID: UUID?, in eligible: [Vacancy]) -> (Vacancy, Vacancy)? {
        guard let firstID, let secondID, firstID != secondID,
              let first = eligible.first(where: { $0.id == firstID }), let second = eligible.first(where: { $0.id == secondID }) else { return nil }
        return (first, second)
    }
    public static func displayValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Не указано" : trimmed
    }
}
