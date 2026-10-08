import XCTest
import CopilotCore

final class TrackerStatisticsTests: XCTestCase {
    func testCompletedDurationsIncludeReturnVisitsAndArchivedCardsButExcludeOpenStage() {
        let stages = Array(VacancyStage.standard.prefix(3))
        let start = Date(timeIntervalSince1970: 1000)
        let day = 86_400.0
        let first = Vacancy(stageID: stages[2].id, company: "A", title: "Go", createdAt: start)
        let archived = Vacancy(stageID: stages[1].id, company: "B", title: "Go", isArchived: true, createdAt: start)
        let events = [
            VacancyTransition(vacancyID: first.id, fromStageID: stages[0].id, toStageID: stages[1].id, happenedAt: start.addingTimeInterval(10 * day)),
            VacancyTransition(vacancyID: first.id, fromStageID: stages[1].id, toStageID: stages[0].id, happenedAt: start.addingTimeInterval(20 * day)),
            VacancyTransition(vacancyID: first.id, fromStageID: stages[0].id, toStageID: stages[2].id, happenedAt: start.addingTimeInterval(30 * day)),
            VacancyTransition(vacancyID: archived.id, fromStageID: stages[0].id, toStageID: stages[1].id, happenedAt: start.addingTimeInterval(20 * day))
        ]
        let result = TrackerStatistics.stageDurations(stages: stages, vacancies: [first, archived, first], transitions: events.reversed() + [events[0]])
        XCTAssertEqual(result.map(\.completedCount), [3, 1, 0])
        XCTAssertEqual(result[0].averageSeconds ?? -1, 40 * day / 3, accuracy: 0.0001)
        XCTAssertEqual(result[1].averageSeconds, 10 * day)
        XCTAssertNil(result[2].averageSeconds)
    }

    func testInvalidDatesForeignEventsAndBrokenChainsDoNotInventDurations() {
        let stages = Array(VacancyStage.standard.prefix(3))
        let start = Date(timeIntervalSince1970: 1000)
        let vacancy = Vacancy(stageID: stages[2].id, company: "A", title: "Go", createdAt: start)
        let events = [
            VacancyTransition(vacancyID: UUID(), fromStageID: stages[0].id, toStageID: stages[1].id, happenedAt: start.addingTimeInterval(100)),
            VacancyTransition(vacancyID: vacancy.id, fromStageID: stages[0].id, toStageID: stages[1].id, happenedAt: start.addingTimeInterval(-10)),
            VacancyTransition(vacancyID: vacancy.id, fromStageID: stages[0].id, toStageID: stages[0].id, happenedAt: start.addingTimeInterval(10)),
            VacancyTransition(vacancyID: vacancy.id, fromStageID: stages[0].id, toStageID: stages[1].id, happenedAt: start.addingTimeInterval(20)),
            VacancyTransition(vacancyID: vacancy.id, fromStageID: stages[2].id, toStageID: stages[0].id, happenedAt: start.addingTimeInterval(30)),
            VacancyTransition(vacancyID: vacancy.id, fromStageID: stages[1].id, toStageID: stages[2].id, happenedAt: start.addingTimeInterval(50)),
            VacancyTransition(vacancyID: vacancy.id, fromStageID: stages[2].id, toStageID: stages[0].id, happenedAt: Date(timeIntervalSince1970: .infinity))
        ]
        let result = TrackerStatistics.stageDurations(stages: stages, vacancies: [vacancy], transitions: events)
        XCTAssertEqual(result.map(\.completedCount), [1, 1, 0])
        XCTAssertEqual(result[0].averageSeconds, 20)
        XCTAssertEqual(result[1].averageSeconds, 30)
        XCTAssertTrue(TrackerStatistics.stageDurations(stages: stages, vacancies: [], transitions: events).allSatisfy { $0.averageSeconds == nil })
    }

    func testExplicitEntryStartsTimingAtEntryAndZeroCompletedIntervalIsRealData() {
        let stages = Array(VacancyStage.standard.prefix(2))
        let start = Date(timeIntervalSince1970: 1000)
        let vacancy = Vacancy(stageID: stages[1].id, company: "A", title: "Go", createdAt: start)
        let entry = VacancyTransition(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, vacancyID: vacancy.id,
                                      fromStageID: nil, toStageID: stages[0].id, happenedAt: start.addingTimeInterval(100))
        let exit = VacancyTransition(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, vacancyID: vacancy.id,
                                     fromStageID: stages[0].id, toStageID: stages[1].id, happenedAt: entry.happenedAt)
        let result = TrackerStatistics.stageDurations(stages: stages, vacancies: [vacancy], transitions: [entry, exit])
        XCTAssertEqual(result[0].completedCount, 1)
        XCTAssertEqual(result[0].averageSeconds, 0)
        XCTAssertNil(result[1].averageSeconds)
    }

    func testComparisonRequiresTwoDistinctEligibleCardsAndPreservesMissingValues() {
        let stages = Array(VacancyStage.standard.prefix(2))
        let salary = Vacancy(stageID: stages[0].id, company: "A", title: "Go", salary: "200–300")
        let format = Vacancy(stageID: stages[1].id, company: "B", title: "Go", workFormat: "Удалённо")
        let empty = Vacancy(stageID: stages[0].id, company: "C", title: "Go", grade: "  \n")
        let archived = Vacancy(stageID: stages[0].id, company: "D", title: "Go", salary: "400", isArchived: true)
        let eligible = OfferComparison.eligible([salary, format, empty, archived])
        XCTAssertEqual(eligible.map(\.id), [salary.id, format.id])
        XCTAssertEqual(OfferComparison.eligible([salary, format], stageIDs: [stages[1].id]).map(\.id), [format.id])
        XCTAssertTrue(OfferComparison.eligible([salary, format], stageIDs: []).isEmpty)
        XCTAssertNil(OfferComparison.pair(firstID: salary.id, secondID: salary.id, in: eligible))
        XCTAssertNil(OfferComparison.pair(firstID: salary.id, secondID: empty.id, in: eligible))
        XCTAssertNotNil(OfferComparison.pair(firstID: salary.id, secondID: format.id, in: eligible))
        XCTAssertEqual(OfferComparison.displayValue(" \n"), "Не указано")
        XCTAssertEqual(OfferComparison.displayValue("  200–300  "), "200–300")
    }
}
