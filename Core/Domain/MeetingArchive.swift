import Foundation

public struct MeetingArchive: Codable, Sendable {
    public let version: Int
    public let meeting: Meeting
    public let subchats: [Subchat]
    public let messages: [ChatMessage]
    public init(meeting: Meeting, subchats: [Subchat], messages: [ChatMessage]) {
        version = 1; self.meeting = meeting
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
