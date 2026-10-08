import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import CopilotCore

@MainActor
struct NotesView: View {
    @Bindable var app: AppModel
    var searchQuery = ""
    @State private var confirmDelete = false
    @State private var showPreview = false
    @State private var textSelection = NSRange(location: 0, length: 0)
    @State private var hasMultipleSelections = false
    @State private var inspectedNote: Note?
    private var visibleNotes: [Note] {
        app.notes.notes
    }
    var body: some View {
        @Bindable var model = app.notes
        HSplitView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Заметки").font(.title2.bold())
                Text("\(model.totalNoteCount) заметок · загружено \(model.notes.count) · \(model.folders.filter { !$0.name.isEmpty }.count) папок")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                if model.isSearching { ProgressView("Поиск заметок…").controlSize(.small) }
                if !model.query.isEmpty, NoteChunker.ftsQuery(model.query) == nil {
                    Text("Введите слово из двух или более символов.").font(.caption).foregroundStyle(.secondary)
                } else if !model.query.isEmpty, model.notes.isEmpty, !model.isSearching {
                    Text("Заметки не найдены. Измените или очистите поиск.").font(.caption).foregroundStyle(.secondary)
                }
                List {
                    Section {
                        Button { model.selectedFolder = nil } label: { Label("Все заметки", systemImage: "doc.text").badge(model.folders.reduce(0) { $0 + $1.count }) }.buttonStyle(.plain)
                        Button { model.selectedFolder = "" } label: { Label("Без папки", systemImage: "folder").badge(model.folders.first { $0.name.isEmpty }?.count ?? 0) }.buttonStyle(.plain)
                        ForEach(model.folders.filter { !$0.name.isEmpty }) { folder in
                            Button { model.selectedFolder = folder.name } label: { Label(folder.name, systemImage: "folder.fill").badge(folder.count) }.buttonStyle(.plain)
                        }
                    }
                    Section("Заметки") {
                        ForEach(visibleNotes) { note in
                            Button { model.select(note) } label: {
                                VStack(alignment: .leading) {
                                    Label(note.title, systemImage: note.isPinned ? "pin.fill" : "doc.text")
                                    Text(note.tags.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                        if model.hasMore {
                            Button(model.isLoadingMore ? "Загрузка…" : "Загрузить ещё 50") { Task { await model.loadMore() } }
                                .disabled(model.isSearching || model.isLoadingMore)
                        }
                    }
                }
                Button { model.create() } label: {
                    Label("Новая заметка", systemImage: "plus")
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .foregroundStyle(.black.opacity(0.75))
                        .background(.white, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
                HStack {
                    Button("Папка", systemImage: "folder.badge.plus") { }.disabled(true).help("Папка создаётся при сохранении заметки с заполненным полем «Папка»")
                    Button("Файлы", systemImage: "square.and.arrow.up") { Task { await importNote() } }
                }.frame(maxWidth: .infinity)
                Button("Проект", systemImage: "doc.badge.gearshape") { }.frame(maxWidth: .infinity).disabled(true).help("Проекты ещё не подключены")
            }.padding().frame(minWidth: 300, idealWidth: 340, maxWidth: 370).background(DesignTokens.sidebar)
            VStack(alignment: .leading, spacing: 12) {
                if let note = model.edited {
                    HStack {
                        TextField("Название", text: noteBinding(\.title, default: "")).font(.title2.bold())
                        Toggle("Использовать RAG", isOn: noteBinding(\.allowAI, default: false)).toggleStyle(.switch)
                        HMStatusPill(text: note.allowAI ? "RAG-индекс" : "Локально", color: note.allowAI ? DesignTokens.success : .secondary)
                        Button("Загрузить файл", systemImage: "arrow.up.doc") { Task { await importNote() } }
                    }
                    TextField("Папка", text: Binding(
                        get: { model.edited?.folder ?? "" },
                        set: { model.edited?.folder = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                    ))
                    TextField("Теги через запятую", text: $model.tagsText)
                    HStack {
                        Toggle("Закрепить", isOn: noteBinding(\.isPinned, default: false))
                        Toggle("В архив", isOn: noteBinding(\.isArchived, default: false))
                        Toggle("Предпросмотр Markdown", isOn: $showPreview)
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 7) {
                            ForEach(MarkdownFormat.allCases) { format in
                                Button { formatText(format) } label: {
                                    if let level = headingLevel(for: format) {
                                        Text("H\(level)").font(.system(size: 13, weight: .semibold)).frame(width: 25, height: 25)
                                    } else { Image(systemName: symbol(for: format)).frame(width: 25, height: 25) }
                                }
                                .buttonStyle(.borderless).help(format.title).accessibilityLabel(format.title)
                                .disabled(showPreview || model.isBusy)
                            }
                        }.padding(6)
                    }.frame(height: 42).background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 8))
                    ZStack {
                        MarkdownTextEditor(text: noteBinding(\.markdown, default: ""), selection: $textSelection,
                                           hasMultipleSelections: $hasMultipleSelections, fontSize: app.preferences.messageFontSize,
                                           isPresented: !showPreview,
                                           onLimitExceeded: { model.status = "Текст заметки ограничен 1 МБ. Сократите текст перед вставкой." })
                            .id(note.id)
                            .opacity(showPreview ? 0 : 1).allowsHitTesting(!showPreview).accessibilityHidden(showPreview)
                        if showPreview { ScrollView { AnswerTextView(text: note.markdown) } }
                    }
                    Text("Разрешение выключено по умолчанию. Дополнительно нужно включить поиск заметок в настройках активного контекста.").font(.caption)
                    if let path = note.sourcePath {
                        Text("Источник: \(URL(fileURLWithPath: path).lastPathComponent)").font(.caption)
                        Text("SHA-256 исходного файла: \(note.sourceHash ?? "нет")").font(.caption2).textSelection(.enabled)
                    }
                    HStack {
                        Button("Сохранить") { model.save() }.buttonStyle(HMPrimaryButtonStyle()).disabled(model.isBusy || !model.hasEdits)
                        Button("Отменить правки") { model.cancelEdits() }.disabled(model.isBusy)
                        Button("Поисковый индекс") { inspectedNote = note }.disabled(model.isBusy || !model.canInspectIndex)
                            .help("Показывает фрагменты сохранённой версии заметки")
                        Menu("Экспорт") {
                            Button("Только Markdown") { Task { await exportNote(note, archive: false) } }
                            Button("Заметка с тегами — JSON") { Task { await exportNote(note, archive: true) } }
                        }
                        Button("Удалить", role: .destructive) { confirmDelete = true }.disabled(model.isBusy)
                        if model.isBusy { Button("Отменить индексацию") { model.cancelSave() } }
                    }
                } else {
                    VStack(spacing: 14) {
                        Text("Выберите заметку или создайте новую").font(.title3.bold())
                        Text("Здесь можно хранить контекст для подготовки: подтверждённые факты, готовые ответы и технические заметки. AI получает только разрешённые заметки активного профиля, когда RAG включён в контексте.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(3)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }.padding().frame(minWidth: 460).background(DesignTokens.canvas)
        }.background(DesignTokens.canvas)
            .onChange(of: model.edited?.id) { _, _ in resetSelection() }
            .onChange(of: app.profile) { _, _ in inspectedNote = nil; resetSelection() }
            .task(id: NoteListTaskID(profile: app.profile, query: searchQuery, folder: model.selectedFolder, archived: model.includeArchived)) {
                do {
                    try await Task.sleep(for: .milliseconds(200))
                    try Task.checkCancellation()
                    model.query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    await model.refresh()
                } catch is CancellationError { }
                catch { }
            }
            .confirmationDialog("Удалить заметку и её поисковый индекс?", isPresented: $confirmDelete) {
                Button("Удалить", role: .destructive) { Task { await model.deleteSelected() } }
            }
            .confirmationDialog("Отбросить правки и открыть другую заметку?", isPresented: Binding(get: { model.pendingSelection != nil }, set: { if !$0 { model.pendingSelection = nil } })) {
                Button("Отбросить правки", role: .destructive) { model.confirmSelection() }
            }
            .confirmationDialog("Отбросить правки и создать новую заметку?", isPresented: $model.confirmNew) {
                Button("Отбросить правки", role: .destructive) { model.newDraft() }
            }
            .sheet(item: $model.pendingImport) { note in
                VStack(alignment: .leading, spacing: 12) {
                    Text("Предпросмотр импорта").font(.title2)
                    Text(note.title)
                    Text("Источник: \(note.sourcePath ?? "")").font(.caption).textSelection(.enabled)
                    Text(model.importExplanation).font(.caption)
                    Text("Теги: " + note.tags.joined(separator: ", ")).font(.caption)
                    Text("AI-доступ выключен. Файл пользователя не изменяется.").font(.caption)
                    ScrollView { Text(note.markdown).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack {
                        Button("Отмена") { model.pendingImport = nil }
                        Button("Открыть как черновик") { model.acceptImport() }
                    }
                }.padding().frame(width: 630, height: 530)
            }
            .sheet(item: $inspectedNote) { note in NoteIndexView(model: model, note: note) }
    }

    private func symbol(for format: MarkdownFormat) -> String {
        switch format {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .link: "link"
        case .inlineCode: "chevron.left.forwardslash.chevron.right"
        case .codeBlock: "curlybraces"
        case .heading1, .heading2, .heading3: "textformat.size"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .quote: "quote.bubble"
        case .horizontalRule: "minus"
        case .table: "tablecells"
        }
    }
    private func headingLevel(for format: MarkdownFormat) -> Int? {
        switch format {
        case .heading1: 1
        case .heading2: 2
        case .heading3: 3
        default: nil
        }
    }
    private func formatText(_ format: MarkdownFormat) {
        guard let note = app.notes.edited else { return }
        if hasMultipleSelections {
            app.notes.status = "Для форматирования выберите один фрагмент текста."; return
        }
        guard let edit = MarkdownEditing.apply(format, to: note.markdown, selection: textSelection) else {
            app.notes.status = "Форматирование не выполнено: проверьте выделение и лимит текста 1 МБ."; return
        }
        app.notes.edited?.markdown = edit.text
        textSelection = edit.selection
    }
    private func resetSelection() {
        textSelection = NSRange(location: 0, length: 0); hasMultipleSelections = false
    }
    private func noteBinding<T>(_ path: WritableKeyPath<Note, T>, default fallback: T) -> Binding<T> {
        Binding(get: { app.notes.edited?[keyPath: path] ?? fallback }, set: { app.notes.edited?[keyPath: path] = $0 })
    }
    private func importNote() async {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .plainText, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]
        guard await panel.begin() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            let maximum = url.pathExtension.lowercased() == "json" ? 8_388_608 : 1_048_576
            guard attributes.isRegularFile == true, let count = attributes.fileSize, count <= maximum else { throw LocalStoreError.invalidData }
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let data = try handle.read(upToCount: maximum + 1) ?? Data()
            guard data.count <= maximum else { throw LocalStoreError.invalidData }
            if url.pathExtension.lowercased() == "json" {
                app.notes.prepareArchiveImport(try NoteArchive.decode(data), source: url); return
            }
            guard let text = String(data: data, encoding: .utf8) else { throw LocalStoreError.invalidData }
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            app.notes.prepareImport(text: text, source: url, hash: hash)
        } catch { app.notes.status = "Не удалось импортировать файл. Нужен UTF-8 текст до 1 МБ либо JSON-архив заметки до 8 МБ с поддерживаемой версией и корректной контрольной суммой." }
    }
    private func exportNote(_ note: Note, archive: Bool) async {
        var note = note
        note.tags = Array(Set(app.notes.tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        guard note.isValid else { app.notes.status = "Проверьте поля заметки перед экспортом."; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = archive ? "note.json" : "note.md"
        panel.allowedContentTypes = archive ? [.json] : [UTType(filenameExtension: "md") ?? .plainText]
        guard await panel.begin() == .OK, let url = panel.url else { return }
        do {
            let data = try archive ? NoteArchive(note: note).encode() : Data(note.markdown.utf8)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            app.notes.status = archive ? "Заметка и теги экспортированы. Абсолютный исходный путь и разрешение AI не включены." : "Текст экспортирован в Markdown. Для сохранения тегов используйте JSON."
        } catch { app.notes.status = "Экспорт заметки не выполнен." }
    }
}

private struct NoteListTaskID: Hashable {
    let profile: ProfileID
    let query: String
    let folder: String?
    let archived: Bool
}
