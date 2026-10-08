import Foundation

public enum TranscriptSpeaker: String, Codable, Sendable {
    case interviewer, candidate
    public var title: String { self == .interviewer ? "Собеседник" : "Максим" }
}

public struct TranscriptEntry: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let segmentID: UUID
    public let speaker: TranscriptSpeaker
    public let text: String
    public let startedAt: TimeInterval
    public let duration: TimeInterval
    public let isFinal: Bool
    public let isDemo: Bool?
    public let recordedAt: Date?

    public init(result: TranscriptResult, maximumCharacters: Int = 4_000, recordedAt: Date = Date()) {
        id = result.id; segmentID = result.segmentID
        speaker = result.source == .system ? .interviewer : .candidate
        text = String(result.text.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
            .prefix(min(4_000, max(1, maximumCharacters))))
        startedAt = result.startedAt; duration = result.duration; isFinal = true
        isDemo = result.isDemo; self.recordedAt = recordedAt
    }
}

public struct TranscriptTimeline: Codable, Equatable, Sendable {
    public private(set) var entries: [TranscriptEntry] = []
    public private(set) var compactedInterviewerCount = 0
    public private(set) var compactedCandidateCount = 0
    private var compactedHighlights: [String] = []
    public var compactedCount: Int { compactedInterviewerCount + compactedCandidateCount }
    public let maximumEntries: Int
    public let maximumCharacters: Int

    public init(maximumEntries: Int = 50, maximumCharacters: Int = 12_000) {
        self.maximumEntries = min(200, max(1, maximumEntries))
        self.maximumCharacters = min(50_000, max(256, maximumCharacters))
    }

    private enum CodingKeys: String, CodingKey {
        case entries, compactedInterviewerCount, compactedCandidateCount, compactedHighlights
        case maximumEntries, maximumCharacters
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        entries = try values.decode([TranscriptEntry].self, forKey: .entries)
        compactedInterviewerCount = try values.decode(Int.self, forKey: .compactedInterviewerCount)
        compactedCandidateCount = try values.decode(Int.self, forKey: .compactedCandidateCount)
        compactedHighlights = try values.decode([String].self, forKey: .compactedHighlights)
        maximumEntries = try values.decode(Int.self, forKey: .maximumEntries)
        maximumCharacters = try values.decode(Int.self, forKey: .maximumCharacters)
        guard (1...200).contains(maximumEntries), (256...50_000).contains(maximumCharacters),
              entries.count <= maximumEntries, entries.reduce(0, { $0 + $1.text.count }) <= maximumCharacters,
              Set(entries.map(\.segmentID)).count == entries.count, Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ !$0.text.isEmpty && $0.text.count <= 4_000 && $0.isFinal &&
                  $0.startedAt.isFinite && $0.startedAt >= 0 && $0.duration.isFinite && $0.duration > 0 && $0.duration <= 60 }),
              (0...1_000_000).contains(compactedInterviewerCount), (0...1_000_000).contains(compactedCandidateCount),
              compactedHighlights.count <= 4, compactedHighlights.allSatisfy({ $0.count <= 300 }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Повреждена ограниченная история расшифровок"))
        }
    }

    public mutating func append(_ result: TranscriptResult) {
        let entry = TranscriptEntry(result: result, maximumCharacters: maximumCharacters)
        guard !entry.text.isEmpty, entry.startedAt.isFinite, entry.startedAt >= 0,
              entry.duration.isFinite, entry.duration > 0, entry.duration <= 60 else { return }
        if let index = entries.firstIndex(where: { $0.segmentID == entry.segmentID }) {
            entries[index] = TranscriptEntry(result: result, maximumCharacters: maximumCharacters,
                                            recordedAt: entries[index].recordedAt ?? Date())
        }
        else { entries.append(entry) }
        while entries.count > maximumEntries || entries.reduce(0, { $0 + $1.text.count }) > maximumCharacters {
            compact(entries.removeFirst())
        }
    }

    public mutating func clear() {
        entries.removeAll(); compactedHighlights.removeAll()
        compactedInterviewerCount = 0; compactedCandidateCount = 0
    }

    public func recentContext(maximumCharacters limit: Int = 4_000) -> String {
        let bounded = min(maximumCharacters, max(1, limit))
        var selected: [String] = []
        var used = 0
        for entry in entries.reversed() {
            let line = "[\(entry.speaker.title)] \(entry.text)"
            guard used + line.count + (selected.isEmpty ? 0 : 1) <= bounded else {
                if selected.isEmpty {
                    let label = "[\(entry.speaker.title)] "
                    selected.append(label + String(entry.text.suffix(max(0, bounded - label.count))))
                }
                break
            }
            selected.append(line); used += line.count + (selected.count == 1 ? 0 : 1)
        }
        return selected.reversed().joined(separator: "\n")
    }

    public func contextWindow(maximumCharacters limit: Int = 4_000) -> String {
        let bounded = min(maximumCharacters, max(128, limit))
        let summary = compactedSummary(maximumCharacters: min(1_000, bounded / 3))
        let separator = summary.isEmpty ? 0 : 1
        let recent = recentContext(maximumCharacters: max(1, bounded - summary.count - separator))
        if summary.isEmpty { return recent }
        if recent.isEmpty { return summary }
        return summary + "\n" + recent
    }

    private mutating func compact(_ entry: TranscriptEntry) {
        if entry.speaker == .interviewer { compactedInterviewerCount += 1 }
        else { compactedCandidateCount += 1 }
        compactedHighlights.append("[\(entry.speaker.title)] \(String(entry.text.prefix(240)))")
        if compactedHighlights.count > 4 { compactedHighlights.removeFirst(compactedHighlights.count - 4) }
    }

    public func compactedSummary(maximumCharacters limit: Int = 1_000) -> String {
        guard compactedCount > 0 else { return "" }
        let limit = min(1_000, max(1, limit))
        let header = "[Ранее] Исключено дословных реплик: собеседник — \(compactedInterviewerCount), Максим — \(compactedCandidateCount)."
        guard header.count < limit else { return String(header.prefix(limit)) }
        var lines = [header]
        var used = header.count
        for highlight in compactedHighlights.reversed() {
            guard used + highlight.count + 1 <= limit else { continue }
            lines.insert(highlight, at: 1); used += highlight.count + 1
        }
        return lines.joined(separator: "\n")
    }
}

public protocol TranscriptRepository: Sendable {
    func transcriptTimeline(meetingID: UUID, profile: ProfileID) async throws -> TranscriptTimeline
    func saveTranscriptTimeline(_ timeline: TranscriptTimeline, meetingID: UUID, profile: ProfileID) async throws
}
