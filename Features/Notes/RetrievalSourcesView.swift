import SwiftUI
import CopilotCore

@MainActor
struct RetrievalSourcesView: View {
    let app: AppModel
    private var conversation: ConversationModel { app.conversation }
    var body: some View {
        if !conversation.retrievedNotes.isEmpty {
            DisclosureGroup("Источники из локальных заметок (\(conversation.retrievedNotes.count))") {
                ForEach(conversation.retrievedNotes) { source in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("\(source.title) · фрагмент \(source.index + 1)").font(.caption.bold())
                            Spacer()
                            Text(conversation.includedNoteIDs.contains(source.id) ? "Включён в запрос" : "Не включён").font(.caption2)
                        }
                        Text(source.tags.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary)
                        Button("Открыть заметку") {
                            Task { await app.notes.openSource(source.noteID); app.requestedSection = .notes }
                        }.font(.caption)
                        Text(source.text).font(.caption).textSelection(.enabled)
                        if let score = source.score { Text("FTS BM25: \(score.formatted(.number.precision(.fractionLength(5)))) · меньше — выше совпадение").font(.caption2) }
                    }.padding(.vertical, 6)
                }
            }
        }
    }
}
