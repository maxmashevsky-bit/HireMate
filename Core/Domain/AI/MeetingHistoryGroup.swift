import Foundation

/// Представление событий без изменения хронологии сообщений, транскрипций или контекста AI.
public enum MeetingHistoryGroup: Identifiable, Sendable, Equatable {
    case message(ChatMessage)
    case transcripts([TranscriptEntry])

    public var id: String {
        switch self {
        case .message(let message): "message." + message.id.uuidString
        case .transcripts(let entries): "transcripts." + (entries.first?.id.uuidString ?? "empty")
        }
    }

    public static func chronological(messages: [ChatMessage], transcripts: [TranscriptEntry]) -> [Self] {
        var events: [(date: Date, order: Int, group: Self)] = []
        for message in messages { events.append((message.createdAt, events.count, .message(message))) }
        for entry in transcripts { events.append((entry.recordedAt ?? .distantPast, events.count, .transcripts([entry]))) }
        events.sort { $0.date == $1.date ? $0.order < $1.order : $0.date < $1.date }
        var groups: [Self] = []
        for event in events {
            if case .transcripts(let next) = event.group, let last = groups.last, case .transcripts(let previous) = last {
                groups[groups.count - 1] = .transcripts(previous + next)
            } else { groups.append(event.group) }
        }
        return groups
    }
}
