import XCTest
import CopilotCore

final class MeetingArchiveTests: XCTestCase {
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
