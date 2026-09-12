import SwiftUI

@MainActor
struct ContextUsageView: View {
    let conversation: ConversationModel

    var body: some View {
        if conversation.requestedTranscriptCharacters > 0 || conversation.contextWasTruncated || conversation.lastLLMRequestMilliseconds != nil {
            VStack(alignment: .leading, spacing: 4) {
                if conversation.requestedTranscriptCharacters > 0 {
                    if conversation.includedTranscriptCharacters > 0 {
                        Label("Расшифровка в контексте: \(conversation.includedTranscriptCharacters) символов",
                              systemImage: "text.bubble")
                    } else {
                        Label("Расшифровка не поместилась в лимит контекста", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                if conversation.contextWasTruncated {
                    Text("Контекст сокращён до настроенного лимита модели.")
                        .foregroundStyle(.orange)
                }
                if let duration = conversation.lastLLMRequestMilliseconds {
                    HStack(spacing: 10) {
                        if let first = conversation.lastFirstTokenMilliseconds {
                            Label("первый токен \(first) мс", systemImage: "timer")
                        }
                        Text("весь запрос \(duration) мс")
                        Text(conversation.lastLLMRequestSucceeded == true ? "успешно" : "не завершён")
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    Text("Метрика локальная: содержимое запроса и ответа в неё не записывается.")
                        .foregroundStyle(.secondary)
                }
            }.font(.caption)
        }
    }
}
