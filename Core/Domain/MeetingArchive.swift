import Foundation

public struct MeetingArchive: Codable, Sendable {
    public let version: Int
    public let meeting: Meeting
    public let subchats: [Subchat]
    public let messages: [ChatMessage]
    public let transcriptTimeline: TranscriptTimeline?
    public init(meeting: Meeting, subchats: [Subchat], messages: [ChatMessage], transcriptTimeline: TranscriptTimeline? = nil) {
        version = 1; self.meeting = meeting
        self.transcriptTimeline = transcriptTimeline
        self.subchats = subchats.filter { $0.meetingID == meeting.id }
        let ids = Set(self.subchats.map(\.id))
        self.messages = messages.filter { ids.contains($0.subchatID) }
    }
    public func markdown() -> String {
        func heading(_ text: String) -> String {
            text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        }
        var lines = ["# \(heading(meeting.title))", "", "Профиль: \(meeting.profileID.title)",
                     "Дата: \(meeting.createdAt.ISO8601Format())", "",
                     "Экспорт текста. Изображения, аудио и ключи API в файл не включены.", ""]
        if let timeline = transcriptTimeline, !timeline.entries.isEmpty || timeline.compactedCount > 0 {
            lines += ["## Расшифровки", "", "Ограниченная локальная история: последние реплики и дословная выжимка старых. Полный звук в файл не включён.", ""]
            let summary = timeline.compactedSummary()
            if !summary.isEmpty { lines += [summary, ""] }
            for entry in timeline.entries {
                let demo = entry.isDemo == true ? " · учебный пример, демо" : ""
                let time = entry.recordedAt.map { " · " + $0.ISO8601Format() } ?? ""
                lines += ["### \(entry.speaker.title)\(demo)\(time)", "", entry.text, ""]
            }
        }
        for chat in subchats where chat.meetingID == meeting.id {
            lines += ["## \(heading(chat.title))", ""]
            let history = messages.filter { $0.subchatID == chat.id }
            if history.isEmpty { lines += ["В этом поддиалоге пока нет сообщений.", ""] }
            for message in history {
                let role: String
                switch message.role {
                case .user: role = "Максим"
                case .assistant: role = message.isDemo ? "Учебный пример · демо" : "Ответ AI"
                case .system: role = "Контекст"
                }
                let state: String
                switch message.state {
                case .complete: state = ""
                case .cancelled: state = " · остановлено"
                case .failed: state = " · не завершено"
                }
                lines += ["### \(role)\(state)", "", message.content, ""]
            }
        }
        return lines.joined(separator: "\n")
    }
}
