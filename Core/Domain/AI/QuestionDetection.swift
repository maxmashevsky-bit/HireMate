import Foundation

/// Дешёвая локальная эвристика. System audio считается речью собеседника,
/// но результат только предлагается пользователю и ничего не отправляет сам.
public struct QuestionDetector: Sendable {
    public init() {}

    public func candidate(from transcript: TranscriptResult) -> String? {
        guard transcript.source == .system else { return nil }
        let text = transcript.text.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...1_500).contains(text.count) else { return nil }
        if text.hasSuffix("?") || text.hasSuffix("？") { return text }

        var words = text.lowercased().split(separator: " ").map(String.init)
        let leading = Set(["а", "и", "ну", "теперь", "пожалуйста", "so", "and", "now", "please"])
        while words.count > 1, leading.contains(words[0].trimmingCharacters(in: .punctuationCharacters)) {
            words.removeFirst()
        }
        guard words.count >= 3 else { return nil }
        let normalized = words.joined(separator: " ")
        let prefixes = [
            "как ", "почему ", "зачем ", "что ", "кто ", "где ", "когда ", "какой ", "какая ", "какие ",
            "сколько ", "можете ", "можешь ", "расскажите ", "расскажи ", "объясните ", "объясни ",
            "опишите ", "опиши ", "напишите ", "напиши ", "реализуйте ",
            "how ", "why ", "what ", "who ", "where ", "when ", "which ", "can you ", "could you ",
            "would you ", "tell me ", "explain ", "describe ", "implement ", "write "
        ]
        return prefixes.contains(where: normalized.hasPrefix) ? text : nil
    }
}
