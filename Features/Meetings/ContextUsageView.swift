import SwiftUI

@MainActor
struct ContextUsageView: View {
    let conversation: ConversationModel

    var body: some View {
        if conversation.requestedTranscriptCharacters > 0 || conversation.contextWasTruncated {
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
            }.font(.caption)
        }
    }
}
