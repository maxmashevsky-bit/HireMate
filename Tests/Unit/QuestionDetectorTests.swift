import XCTest
import CopilotCore

final class QuestionDetectorTests: XCTestCase {
    private let detector = QuestionDetector()

    private func transcript(_ text: String, source: AudioSource = .system) -> TranscriptResult {
        let segment = AudioSegment(source: source, startedAt: 1, samples: [0.1], reason: "Тест")
        return TranscriptResult(segment: segment, text: text, isDemo: false)
    }

    func testDetectsRussianAndEnglishQuestionsLocally() {
        XCTAssertEqual(detector.candidate(from: transcript("Как устроен планировщик Go")), "Как устроен планировщик Go")
        XCTAssertEqual(detector.candidate(from: transcript("А теперь расскажите о последнем проекте.")),
                       "А теперь расскажите о последнем проекте.")
        XCTAssertEqual(detector.candidate(from: transcript("Could you explain this race condition")),
                       "Could you explain this race condition")
        XCTAssertEqual(detector.candidate(from: transcript("Ваш ответ?")), "Ваш ответ?")
    }

    func testIgnoresCandidateSpeechAndOrdinaryStatements() {
        XCTAssertNil(detector.candidate(from: transcript("Как я уже говорил, сервис работает.", source: .microphone)))
        XCTAssertNil(detector.candidate(from: transcript("Сервис использует очередь сообщений.")))
        XCTAssertNil(detector.candidate(from: transcript("Как хорошо")))
    }

    func testNormalizesWhitespaceAndBoundsInput() {
        XCTAssertEqual(detector.candidate(from: transcript("  Почему\nвозникает   deadlock?  ")), "Почему возникает deadlock?")
        XCTAssertNil(detector.candidate(from: transcript(String(repeating: "а", count: 1_501) + "?")))
    }
}
