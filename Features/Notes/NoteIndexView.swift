import SwiftUI
import CopilotCore

@MainActor
struct NoteIndexView: View {
    let model: NotesModel
    let note: Note
    @Environment(\.dismiss) private var dismiss
    @State private var page: NoteIndexPage?
    @State private var offset = 0
    @State private var reload = UUID()
    @State private var loading = false
    @State private var rebuilding = false
    @State private var issue: String?
    @State private var loadID = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Поисковый индекс заметки").font(.title2.bold())
                Spacer(); Button("Закрыть") { dismiss() }
            }
            Text("Сохранённая версия на этом Mac. Несохранённые правки редактора сюда не входят; просмотр не отправляет текст в AI.").font(.caption).foregroundStyle(.secondary)
            if loading || rebuilding { ProgressView(rebuilding ? "Пересоздание локального индекса…" : "Чтение индекса…") }
            if let issue { Text(issue).foregroundStyle(.orange) }
            if let page {
                Text(page.note.title).font(.headline)
                Text("Фрагментов: \(page.totalCount) · AI-доступ \(page.note.allowAI ? "разрешён" : "выключен")\(page.note.isArchived ? " · в архиве" : "")").font(.caption)
                Text("Версия текста: \(page.note.contentHash)").font(.caption2).textSelection(.enabled)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if page.fragments.isEmpty { Text("На этой странице фрагментов нет. Обновите индекс или вернитесь к первой странице.").foregroundStyle(.secondary) }
                        ForEach(page.fragments) { fragment in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Фрагмент \(fragment.index + 1)").font(.headline)
                                Text(fragment.text).textSelection(.enabled)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                HStack {
                    Button("Предыдущие") { offset = max(0, offset - 50) }.disabled(loading || rebuilding || offset == 0)
                    Text("Страница \(offset / 50 + 1)").font(.caption)
                    Button("Следующие") { offset += 50 }.disabled(loading || rebuilding || !page.hasNext)
                    Spacer()
                    Button("Обновить") { offset = 0; reload = UUID() }.disabled(loading || rebuilding)
                }
            } else if !loading {
                Button("Повторить") { reload = UUID() }
            }
            Button("Пересоздать индекс сохранённой заметки") {
                Task {
                    rebuilding = true
                    let success = await model.rebuildIndex(noteID: note.id)
                    rebuilding = false
                    if success { offset = 0; reload = UUID() }
                    else { issue = model.status }
                }
            }.disabled(loading || rebuilding || model.isBusy || model.hasEdits || !model.canInspectIndex || model.edited?.id != note.id)
            Text("Пересоздание использует тот же текст и текущую разбивку; дата локального сохранения обновится. Сначала сохраните или отмените правки редактора.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 720, height: 620)
            .task(id: "\(note.id)-\(offset)-\(reload)") { await load() }
    }
    private func load() async {
        let id = UUID(); loadID = id; loading = true; issue = nil; page = nil
        defer { if loadID == id { loading = false } }
        do {
            let result = try await model.indexPage(noteID: note.id, profile: note.profileID, offset: offset)
            try Task.checkCancellation()
            guard loadID == id else { return }
            page = result
        } catch is CancellationError { }
        catch {
            guard loadID == id else { return }
            issue = "Не удалось прочитать сохранённый индекс. Заметка могла измениться или быть удалена; закройте просмотр и повторите сохранение."
        }
    }
}
