import XCTest
import CopilotCore

final class TranscriptTimelineTests: XCTestCase {
    func testPersistentSnapshotPreservesCompactionSpeakersAndTimestamps() throws {
        var timeline = TranscriptTimeline(maximumEntries: 2)
        for index in 0..<8 {
            timeline.append(result("Реплика \(index)", source: index.isMultiple(of: 2) ? .system : .microphone, time: Double(index)))
        }
        let restored = try JSONDecoder().decode(TranscriptTimeline.self, from: JSONEncoder().encode(timeline))
        XCTAssertEqual(restored, timeline)
        XCTAssertEqual(restored.compactedCount, 6)
        XCTAssertEqual(restored.contextWindow(), timeline.contextWindow())
    }

    func testPersistentSnapshotRejectsCorruptBoundsDuplicateSegmentsAndOversizedText() throws {
        var timeline = TranscriptTimeline()
        timeline.append(result("Текст", source: .system))
        let data = try JSONEncoder().encode(timeline)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for mutation in ["bounds", "duplicate", "text", "count"] {
            var json = original
            switch mutation {
            case "bounds": json["maximumEntries"] = 0
            case "count": json["compactedInterviewerCount"] = -1
            case "duplicate":
                let entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
                json["entries"] = entries + entries
            default:
                var entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
                entries[0]["text"] = String(repeating: "x", count: 4_001)
                json["entries"] = entries
            }
            XCTAssertThrowsError(try JSONDecoder().decode(TranscriptTimeline.self, from: JSONSerialization.data(withJSONObject: json)), mutation)
        }
    }

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
        let recordedAt = timeline.entries.first?.recordedAt
        timeline.append(result("Следующая реплика", source: .microphone, time: 2))
        timeline.append(result("Исправленный вариант", source: .system, id: id, time: 1))
        XCTAssertEqual(timeline.entries.count, 2)
        XCTAssertEqual(timeline.entries.first?.text, "Исправленный вариант")
        XCTAssertEqual(timeline.entries.first?.recordedAt, recordedAt)
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

    func testContextWindowAddsBoundedExtractiveCompaction() {
        var timeline = TranscriptTimeline(maximumEntries: 2, maximumCharacters: 1_000)
        timeline.append(result("Первый вопрос про каналы", source: .system, time: 1))
        timeline.append(result("Первый ответ", source: .microphone, time: 2))
        timeline.append(result("Второй вопрос", source: .system, time: 3))
        timeline.append(result("Второй ответ", source: .microphone, time: 4))
        XCTAssertEqual(timeline.compactedInterviewerCount, 1)
        XCTAssertEqual(timeline.compactedCandidateCount, 1)
        let window = timeline.contextWindow(maximumCharacters: 512)
        XCTAssertTrue(window.contains("[Ранее]"))
        XCTAssertTrue(window.contains("Первый вопрос про каналы"))
        XCTAssertTrue(window.hasSuffix("[Собеседник] Второй вопрос\n[Максим] Второй ответ"))
        XCTAssertLessThanOrEqual(window.count, 512)
        timeline.clear()
        XCTAssertEqual(timeline.compactedCount, 0)
    }

    func testHistoryGroupsConsecutiveTranscriptsInEventChronology() {
        let chat = UUID()
        let one = TranscriptEntry(result: result("Первый вопрос", source: .system), recordedAt: Date(timeIntervalSince1970: 1))
        let two = TranscriptEntry(result: result("Уточнение", source: .microphone), recordedAt: Date(timeIntervalSince1970: 2))
        let three = TranscriptEntry(result: result("Ещё уточнение", source: .system), recordedAt: Date(timeIntervalSince1970: 4))
        let question = ChatMessage(subchatID: chat, role: .user, content: "Мой вопрос", createdAt: Date(timeIntervalSince1970: 3))
        let answer = ChatMessage(subchatID: chat, role: .assistant, content: "Ответ", createdAt: Date(timeIntervalSince1970: 5))
        let messages = [answer, question], transcripts = [three, one, two]
        let groups = MeetingHistoryGroup.chronological(messages: messages, transcripts: transcripts)
        XCTAssertEqual(groups, [.transcripts([one, two]), .message(question), .transcripts([three]), .message(answer)])
        XCTAssertEqual(Set(groups.map(\.id)).count, 4)
        XCTAssertEqual(messages, [answer, question])
        XCTAssertEqual(transcripts, [three, one, two])
        let appended = TranscriptEntry(result: result("Новый фрагмент", source: .system), recordedAt: Date(timeIntervalSince1970: 2.5))
        let updated = MeetingHistoryGroup.chronological(messages: messages, transcripts: transcripts + [appended])
        XCTAssertEqual(updated.first?.id, groups.first?.id)
        XCTAssertEqual(MeetingHistoryGroup.chronological(messages: [], transcripts: []), [])
    }

    func testTranscriptMetadataRoundTripAndLegacyUnknownSource() throws {
        let segment = AudioSegment(source: .system, startedAt: 0, samples: [0.1], reason: "Тест")
        let entry = TranscriptEntry(result: TranscriptResult(segment: segment, text: "Учебный текст", isDemo: true),
                                    recordedAt: Date(timeIntervalSince1970: 1_234))
        let data = try JSONEncoder().encode(entry)
        XCTAssertEqual(try JSONDecoder().decode(TranscriptEntry.self, from: data), entry)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "isDemo"); legacy.removeValue(forKey: "recordedAt")
        let restored = try JSONDecoder().decode(TranscriptEntry.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored.text, entry.text)
        XCTAssertNil(restored.isDemo)
        XCTAssertNil(restored.recordedAt)
        let message = ChatMessage(subchatID: UUID(), role: .user, content: "Новое", createdAt: Date(timeIntervalSince1970: 1_235))
        XCTAssertEqual(MeetingHistoryGroup.chronological(messages: [message], transcripts: [restored]),
                       [.transcripts([restored]), .message(message)])
    }
}
