import XCTest
import CopilotCore

final class TranscriptTimelineTests: XCTestCase {
    private func result(_ text: String, source: AudioSource, id: UUID = UUID(), time: Double = 0) -> TranscriptResult {
        let segment = AudioSegment(id: id, source: source, startedAt: time, samples: [0.1], reason: "Тест")
        return TranscriptResult(segment: segment, text: text, isDemo: false)
    }

    func testMapsSourcesToSpeakersAndNormalizesFinalText() {
        var timeline = TranscriptTimeline()
        timeline.append(result("  Как\nработает scheduler? ", source: .system))
        timeline.append(result("Я начну с модели G-M-P.", source: .microphone))
        XCTAssertEqual(timeline.entries.map(\.speaker), [.interviewer, .candidate])
        XCTAssertEqual(timeline.entries.first?.text, "Как работает scheduler?")
        XCTAssertTrue(timeline.entries.allSatisfy(\.isFinal))
    }

    func testRetranscriptionReplacesSameSegmentWithoutReordering() {
        let id = UUID(); var timeline = TranscriptTimeline()
        timeline.append(result("Первый вариант", source: .system, id: id, time: 1))
        timeline.append(result("Следующая реплика", source: .microphone, time: 2))
        timeline.append(result("Исправленный вариант", source: .system, id: id, time: 1))
        XCTAssertEqual(timeline.entries.count, 2)
        XCTAssertEqual(timeline.entries.first?.text, "Исправленный вариант")
    }

    func testBoundsEntriesAndCharactersByRemovingOldest() {
        var timeline = TranscriptTimeline(maximumEntries: 2, maximumCharacters: 256)
        timeline.append(result(String(repeating: "а", count: 150), source: .system, time: 1))
        timeline.append(result(String(repeating: "б", count: 150), source: .microphone, time: 2))
        XCTAssertEqual(timeline.entries.count, 1)
        timeline.append(result("третья", source: .system, time: 3))
        timeline.append(result("четвёртая", source: .microphone, time: 4))
        XCTAssertEqual(timeline.entries.map(\.text), ["третья", "четвёртая"])

        var oversized = TranscriptTimeline(maximumCharacters: 256)
        oversized.append(result(String(repeating: "я", count: 400), source: .system))
        XCTAssertEqual(oversized.entries.count, 1)
        XCTAssertEqual(oversized.entries[0].text.count, 256)
        XCTAssertEqual(oversized.recentContext(maximumCharacters: 128).count, 128)
    }

    func testRecentContextKeepsChronologyAndSpeakerLabels() {
        var timeline = TranscriptTimeline()
        timeline.append(result("Старая длинная реплика", source: .system))
        timeline.append(result("Новый вопрос?", source: .system))
        timeline.append(result("Мой ответ", source: .microphone))
        let context = timeline.recentContext(maximumCharacters: 128)
        XCTAssertTrue(context.hasSuffix("[Собеседник] Новый вопрос?\n[Максим] Мой ответ"))
        XCTAssertLessThanOrEqual(context.count, 128)
    }
}
