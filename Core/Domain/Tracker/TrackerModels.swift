import Foundation

public struct VacancyStage: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var position: Int

    public init(id: UUID = UUID(), name: String, position: Int) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.position = position
    }

    public var isValid: Bool { (1...80).contains(name.count) && position >= 0 }

    public static let standard: [VacancyStage] = [
        "Скрининг", "Фидбек скрининга", "Техничка", "Фидбек технички",
        "Системный дизайн", "Фидбек системного дизайна", "Финалы", "Оффер", "Отказы"
    ].enumerated().map { index, name in
        VacancyStage(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                     name: name, position: index)
    }
}

public struct Vacancy: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var stageID: UUID
    public var company: String
    public var title: String
    public var details: String
    public var salary: String
    public var grade: String
    public var workFormat: String
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), stageID: UUID, company: String, title: String,
                details: String = "", salary: String = "", grade: String = "",
                workFormat: String = "", isArchived: Bool = false,
                createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.stageID = stageID
        self.company = company.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.details = details; self.salary = salary; self.grade = grade; self.workFormat = workFormat
        self.isArchived = isArchived; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public var isValid: Bool {
        (1...160).contains(company.count) && (1...160).contains(title.count) && details.count <= 12_000 &&
        salary.count <= 200 && grade.count <= 100 && workFormat.count <= 200
    }

    public var hasComparisonData: Bool {
        !salary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !grade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !workFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct VacancyTransition: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var vacancyID: UUID
    public var fromStageID: UUID?
    public var toStageID: UUID
    public var happenedAt: Date

    public init(id: UUID = UUID(), vacancyID: UUID, fromStageID: UUID?, toStageID: UUID,
                happenedAt: Date = .now) {
        self.id = id; self.vacancyID = vacancyID; self.fromStageID = fromStageID
        self.toStageID = toStageID; self.happenedAt = happenedAt
    }
}

public protocol TrackerRepository: Sendable {
    func vacancyStages() async throws -> [VacancyStage]
    func saveVacancyStages(_ stages: [VacancyStage]) async throws
    func vacancies(includeArchived: Bool) async throws -> [Vacancy]
    func saveVacancy(_ vacancy: Vacancy) async throws
    func moveVacancy(id: UUID, to stageID: UUID, at date: Date) async throws
    func setVacancyArchived(id: UUID, archived: Bool, at date: Date) async throws
    func vacancyTransitions() async throws -> [VacancyTransition]
}
