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

    public init(result: TranscriptResult, maximumCharacters: Int = 4_000) {
        id = result.id; segmentID = result.segmentID
        speaker = result.source == .system ? .interviewer : .candidate
        text = String(result.text.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
            .prefix(min(4_000, max(1, maximumCharacters))))
        startedAt = result.startedAt; duration = result.duration; isFinal = true
    }
}

public struct TranscriptTimeline: Sendable {
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

    public mutating func append(_ result: TranscriptResult) {
        let entry = TranscriptEntry(result: result, maximumCharacters: maximumCharacters)
        guard !entry.text.isEmpty else { return }
        if let index = entries.firstIndex(where: { $0.segmentID == entry.segmentID }) { entries[index] = entry }
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

    private func compactedSummary(maximumCharacters limit: Int) -> String {
        guard compactedCount > 0 else { return "" }
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
