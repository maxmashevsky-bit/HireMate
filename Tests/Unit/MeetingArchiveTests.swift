import XCTest
import CopilotCore

final class MeetingArchiveTests: XCTestCase {
    func testTranscriptExportPreservesSpeakersDemoAndCompactionAndReadsLegacyJSON() throws {
        let meeting = Meeting(profileID: .technical, title: "История", isEphemeral: false)
        var timeline = TranscriptTimeline(maximumEntries: 1)
        let first = AudioSegment(source: .microphone, startedAt: 1, samples: [0.1], reason: "Тест")
        let second = AudioSegment(source: .system, startedAt: 2, samples: [0.1], reason: "Тест")
        timeline.append(TranscriptResult(segment: first, text: "Мой ответ", isDemo: false))
        timeline.append(TranscriptResult(segment: second, text: "Как работает Go?", isDemo: true))
        let archive = MeetingArchive(meeting: meeting, subchats: [], messages: [], transcriptTimeline: timeline)
        let markdown = archive.markdown()
        XCTAssertTrue(markdown.contains("## Расшифровки"))
        XCTAssertTrue(markdown.contains("[Максим] Мой ответ"))
        XCTAssertTrue(markdown.contains("### Собеседник · учебный пример, демо"))
        XCTAssertTrue(markdown.contains("Как работает Go?"))
        let encoded = try JSONEncoder().encode(archive)
        XCTAssertEqual(try JSONDecoder().decode(MeetingArchive.self, from: encoded).transcriptTimeline, timeline)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "transcriptTimeline")
        let restored = try JSONDecoder().decode(MeetingArchive.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.transcriptTimeline)
        XCTAssertEqual(restored.meeting.id, meeting.id)
    }
    func testMarkdownPreservesCodeAndMarksPartialDemo() {
        let meeting = Meeting(profileID: .liveCoding, title: "Go\nИнтервью", isEphemeral: true)
        let chat = Subchat(meetingID: meeting.id, title: "Задача")
        let code = "```go\nfunc main() {\n    println(1)\n}\n```"
        let message = ChatMessage(subchatID: chat.id, role: .assistant, content: code, state: .cancelled, isDemo: true)
        let text = MeetingArchive(meeting: meeting, subchats: [chat], messages: [message]).markdown()
        XCTAssertTrue(text.contains("# Go Интервью"))
        XCTAssertTrue(text.contains("Go Live Coding"))
        XCTAssertTrue(text.contains("Учебный пример · демо · остановлено"))
        XCTAssertTrue(text.contains(code))
    }
    func testForeignChatAndMessagesAreExcluded() {
        let meeting = Meeting(profileID: .hr, title: "HR", isEphemeral: true)
        let chat = Subchat(meetingID: meeting.id, title: "Основной")
        let foreign = Subchat(meetingID: UUID(), title: "Чужой")
        let message = ChatMessage(subchatID: foreign.id, role: .user, content: "Чужой контекст")
        let archive = MeetingArchive(meeting: meeting, subchats: [chat, foreign], messages: [message])
        XCTAssertEqual(archive.subchats.count, 1)
        XCTAssertTrue(archive.messages.isEmpty)
        XCTAssertFalse(archive.markdown().contains("Чужой"))
        XCTAssertTrue(archive.markdown().contains("пока нет сообщений"))
    }
}
