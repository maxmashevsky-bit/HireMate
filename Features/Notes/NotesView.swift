import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import CopilotCore

@MainActor
struct NotesView: View {
    @Bindable var app: AppModel
    @State private var confirmDelete = false
    @State private var showPreview = false
    var body: some View {
        @Bindable var model = app.notes
        HSplitView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Заметки").font(.title2.bold())
                Text("\(model.notes.count) заметок · \(Set(model.notes.compactMap(\.folder)).count) папок")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                List {
                    Section {
                        Label("Без папки", systemImage: "folder").badge(model.notes.filter { ($0.folder ?? "").isEmpty }.count)
                        ForEach(Array(Set(model.notes.compactMap(\.folder))).sorted(), id: \.self) { folder in
                            Label(folder, systemImage: "folder.fill").badge(model.notes.filter { $0.folder == folder }.count)
                        }
                    }
                    Section("Заметки") {
                        ForEach(model.notes) { note in
                            Button { model.select(note) } label: {
                                VStack(alignment: .leading) {
                                    Label(note.title, systemImage: note.isPinned ? "pin.fill" : "doc.text")
                                    Text(note.tags.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
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
                    Button("Папка", systemImage: "folder.badge.plus") { }
                    Button("Файлы", systemImage: "square.and.arrow.up") { Task { await importNote() } }
                }.frame(maxWidth: .infinity)
                Button("Проект", systemImage: "doc.badge.gearshape") { }.frame(maxWidth: .infinity)
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
                    HStack(spacing: 7) {
                        ForEach(["bold", "italic", "strikethrough", "link", "curlybraces", "list.bullet", "list.number", "quote.bubble", "tablecells"], id: \.self) { symbol in
                            Button { } label: { Image(systemName: symbol).frame(width: 25, height: 25) }.buttonStyle(.borderless)
                        }
                    }.padding(6).background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 8))
                    if showPreview {
                        ScrollView { Text(.init(note.markdown)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    } else {
                        TextEditor(text: noteBinding(\.markdown, default: "")).font(.system(.body, design: .monospaced))
                    }
                    Text("Разрешение выключено по умолчанию. Дополнительно нужно включить поиск заметок в настройках активного контекста.").font(.caption)
                    if let path = note.sourcePath {
                        Text("Источник: \(URL(fileURLWithPath: path).lastPathComponent)").font(.caption)
                        Text("SHA-256 исходного файла: \(note.sourceHash ?? "нет")").font(.caption2).textSelection(.enabled)
                    }
                    HStack {
                        Button("Сохранить") { model.save() }.buttonStyle(HMPrimaryButtonStyle()).disabled(model.isBusy || !model.hasEdits)
                        Button("Отменить правки") { model.cancelEdits() }.disabled(model.isBusy)
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
                        Text("Здесь можно хранить дополнительный контекст для нейросети:\nлегенду о себе, готовые ответы на частые вопросы, технические\nтермины и любую другую информацию. Всё, что вы напишете, ИИ\nбудет учитывать при генерации ответов.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(3)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }.padding().frame(minWidth: 460).background(DesignTokens.canvas)
        }.background(DesignTokens.canvas).task { await model.refresh() }
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
