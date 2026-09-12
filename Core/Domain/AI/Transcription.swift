import Foundation

public enum TranscriptionLanguage: String, CaseIterable, Sendable, Identifiable {
    case automatic = "auto", russian = "ru", english = "en"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .automatic: "Автоматически"
        case .russian: "Русский"
        case .english: "Английский"
        }
    }
}

public struct TranscriptResult: Identifiable, Sendable {
    public let id: UUID
    public let segmentID: UUID
    public let source: AudioSource
    public var text: String
    public let startedAt: TimeInterval
    public let duration: TimeInterval
    public let isDemo: Bool
    public let confidence: Double?
    public init(id: UUID = UUID(), segment: AudioSegment, text: String, isDemo: Bool, confidence: Double? = nil) {
        self.id = id; segmentID = segment.id; source = segment.source; self.text = text
        startedAt = segment.startedAt; duration = segment.duration; self.isDemo = isDemo; self.confidence = confidence
    }
}

public enum TranscriptionEvent: Sendable {
    case partial(String)
    case final(TranscriptResult)
}
public protocol TranscriptionService: Sendable {
    func transcribe(_ segment: AudioSegment, language: TranscriptionLanguage,
                    vocabulary: [String]) -> AsyncThrowingStream<TranscriptionEvent, Error>
}

public struct FakeTranscriptionService: TranscriptionService {
    public init() {}
    public func transcribe(_ segment: AudioSegment, language: TranscriptionLanguage,
                           vocabulary: [String]) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let text = language == .english ? "Demo question: how do goroutines communicate?" : "Демонстрационный вопрос: как взаимодействуют горутины?"
                    var partial = ""
                    for word in text.split(separator: " ") {
                        try await Task.sleep(for: .milliseconds(80))
                        try Task.checkCancellation()
                        partial += (partial.isEmpty ? "" : " ") + word
                        continuation.yield(.partial(partial))
                    }
                    continuation.yield(.final(TranscriptResult(segment: segment, text: text, isDemo: true)))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
