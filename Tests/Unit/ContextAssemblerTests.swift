import XCTest
import CopilotCore

final class ContextAssemblerTests: XCTestCase {
    func testTranscriptIsIncludedAsUntrustedReferenceWithinBudget() throws {
        var configuration = ModelConfiguration()
        configuration.maxContextTokens = 8_000; configuration.reservedOutputTokens = 512
        let request = try BoundedContextAssembler().assemble(
            profile: ContextProfile(id: .technical), history: [], subchatID: UUID(),
            question: "Что ответить?", configuration: configuration, notes: [],
            transcriptContext: "[Собеседник] Как устроен scheduler Go?\n[Максим] Сейчас объясню")
        XCTAssertGreaterThan(request.includedTranscriptCharacters, 0)
        XCTAssertTrue(request.messages.contains { $0.content.contains("<transcript>") && $0.content.contains("[Собеседник]") })
        XCTAssertFalse(request.wasTruncated)
    }

    func testTranscriptIsOmittedBeforeCurrentQuestionWhenBudgetIsTight() throws {
        var configuration = ModelConfiguration()
        configuration.maxContextTokens = 4_096; configuration.reservedOutputTokens = 512
        let request = try BoundedContextAssembler().assemble(
            profile: ContextProfile(id: .technical), history: [], subchatID: UUID(),
            question: "Короткий вопрос", configuration: configuration, notes: [],
            transcriptContext: String(repeating: "длинная реплика ", count: 500))
        XCTAssertEqual(request.includedTranscriptCharacters, 0)
        XCTAssertTrue(request.wasTruncated)
        XCTAssertEqual(request.messages.last?.content, "Короткий вопрос")
    }

    func testTranscriptInputIsCappedAtFourThousandCharacters() throws {
        var configuration = ModelConfiguration()
        configuration.maxContextTokens = 16_384; configuration.reservedOutputTokens = 1_024
        let request = try BoundedContextAssembler().assemble(
            profile: ContextProfile(id: .hr), history: [], subchatID: UUID(),
            question: "Вопрос", configuration: configuration, notes: [],
            transcriptContext: String(repeating: "a", count: 5_000))
        XCTAssertEqual(request.includedTranscriptCharacters, 4_000)
    }
}
