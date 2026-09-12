import Foundation
import Observation
import CopilotCore

@MainActor @Observable
final class NotesModel {
    var query = ""
    var includeArchived = false
    var tagsText = ""
    var edited: Note?
    var pendingSelection: Note?
    var pendingImport: Note?
    var importExplanation = ""
    var confirmNew = false
    var status = "Заметки хранятся только на этом Mac. Поиск не использует AI."
    private(set) var notes: [Note] = []
    private(set) var isBusy = false
    private var baseline: Note?
    private var profile: ProfileID
    private var operationID = UUID()
    private var saveTask: Task<Void, Never>?
    private let repository: any NoteRepository
    init(profile: ProfileID, repository: any NoteRepository) { self.profile = profile; self.repository = repository }
    var hasEdits: Bool { edited != baseline || tagsText != (baseline?.tags.joined(separator: ", ") ?? "") }
    func activateProfile(_ profile: ProfileID) {
        guard self.profile != profile else { return }
        saveTask?.cancel(); operationID = UUID(); isBusy = false
        self.profile = profile; notes = []; edited = nil; baseline = nil; tagsText = ""; query = ""
        pendingSelection = nil; pendingImport = nil; confirmNew = false
        Task { await refresh() }
    }
    func refresh() async {
        let id = operationID; let profile = profile; let query = query; let archive = includeArchived
        do {
            let loaded = try await repository.notes(profile: profile, query: query, includeArchived: archive)
            guard operationID == id, self.query == query, self.includeArchived == archive else { return }
            notes = loaded
        } catch { if operationID == id { status = "Не удалось прочитать заметки." } }
    }
    func openSource(_ id: UUID) async {
        let scope = profile; let operation = operationID
        do {
            let note = try await repository.note(id: id, profile: scope)
            guard operationID == operation else { return }
            select(note)
        } catch { if operationID == operation { status = "Заметка больше не доступна в этом профиле." } }
    }
    func select(_ note: Note) {
        guard note.id != edited?.id, note.profileID == profile else { return }
        if hasEdits { pendingSelection = note } else { applySelection(note) }
    }
    func confirmSelection() { if let next = pendingSelection { applySelection(next) }; pendingSelection = nil }
    private func applySelection(_ note: Note) { edited = note; baseline = note; tagsText = note.tags.joined(separator: ", ") }
    func create() { if hasEdits { confirmNew = true } else { newDraft() } }
    func newDraft() {
        confirmNew = false; edited = Note(profileID: profile); baseline = nil; tagsText = ""
        status = "Новая заметка ещё не сохранена."
    }
    func cancelEdits() { edited = baseline; tagsText = baseline?.tags.joined(separator: ", ") ?? "" }
    func save() {
        guard var note = edited, !isBusy else { return }
        note.tags = Array(Set(tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        guard note.isValid else { status = "Проверьте название, теги и размер текста (до 1 МБ)."; return }
        note.updatedAt = Date(); note.contentHash = Note.hash(note.markdown)
        let snapshot = edited; let tagSnapshot = tagsText; let id = operationID
        isBusy = true; status = "Сохранение и локальная индексация…"
        saveTask = Task { [weak self] in
            guard let self else { return }
            defer { if operationID == id { isBusy = false; saveTask = nil } }
            do {
                try await repository.saveNote(note)
                guard operationID == id else { return }
                // Не затирать новые правки, сделанные во время записи.
                if edited == snapshot && tagsText == tagSnapshot { applySelection(note) }
                else if edited?.id == note.id { baseline = note }
                status = "Заметка сохранена; локальный индекс обновлён."
                await refresh()
            } catch { if operationID == id { status = "Сохранение не завершено. Текст остаётся в редакторе." } }
        }
    }
    func cancelSave() { saveTask?.cancel() }
    func waitForPendingSave() async { await saveTask?.value }
    func deleteSelected() async {
        guard let note = edited, !isBusy else { return }
        let id = operationID
        isBusy = true
        defer { if operationID == id { isBusy = false } }
        do {
            try await repository.deleteNote(id: note.id, profile: profile)
            guard operationID == id else { return }
            if edited?.id == note.id { edited = nil; baseline = nil; tagsText = "" }
            status = "Заметка и индекс удалены."
            await refresh()
        } catch { if operationID == id { status = "Заметка не удалена." } }
    }
    func prepareImport(text: String, source: URL, hash: String) {
        var note = Note(profileID: profile, title: String(source.deletingPathExtension().lastPathComponent.prefix(200)), markdown: text)
        note.sourcePath = source.path; note.sourceHash = hash
        pendingImport = note; importExplanation = "Текстовый файл будет открыт как новая заметка."
    }
    func prepareArchiveImport(_ archive: NoteArchive, source: URL) {
        guard archive.profileID == profile else {
            status = "Архив относится к профилю «\(archive.profileID.title)». Переключите профиль вручную перед импортом."; return
        }
        var note = archive.importedNote(); note.sourcePath = source.path
        pendingImport = note
        importExplanation = "Импортируются теги, закрепление и архивный статус. Будет создана новая заметка с новым ID. AI-доступ выключен. Даты оригинала: \(archive.createdAt.formatted()) — \(archive.updatedAt.formatted())."
    }
    func acceptImport() {
        guard let note = pendingImport, note.profileID == profile, !hasEdits else { return }
        edited = note; baseline = nil; tagsText = note.tags.joined(separator: ", "); pendingImport = nil
        status = "Импорт открыт как черновик. Для записи и индексации нажмите «Сохранить»."
    }
}
