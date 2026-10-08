import Foundation
import Observation
import CopilotCore

@MainActor @Observable
final class NotesModel {
    var query = ""
    var includeArchived = false
    var selectedFolder: String?
    var tagsText = ""
    var edited: Note?
    var pendingSelection: Note?
    var pendingImport: Note?
    var importExplanation = ""
    var confirmNew = false
    var status = "Заметки хранятся только на этом Mac. Поиск не использует AI."
    private(set) var notes: [Note] = []
    private(set) var isBusy = false
    private(set) var isSearching = false
    private(set) var isLoadingMore = false
    private(set) var totalNoteCount = 0
    private(set) var folders: [NoteFolderCount] = []
    private(set) var hasMore = false
    var onLibraryChanged: (@MainActor () -> Void)?
    private var baseline: Note?
    private var profile: ProfileID
    private var operationID = UUID()
    private var refreshID = UUID()
    private var pageRequestID = UUID()
    private var nextOffset = 0
    private var saveTask: Task<Void, Never>?
    private var lastSaveSucceeded = false
    private let repository: any NoteRepository
    init(profile: ProfileID, repository: any NoteRepository) { self.profile = profile; self.repository = repository }
    var hasEdits: Bool { edited != baseline || tagsText != (baseline?.tags.joined(separator: ", ") ?? "") }
    var canInspectIndex: Bool { baseline != nil && baseline?.id == edited?.id && repository is any NoteIndexInspecting }
    func indexPage(noteID: UUID, profile requestedProfile: ProfileID, offset: Int) async throws -> NoteIndexPage {
        guard requestedProfile == profile, let inspector = repository as? any NoteIndexInspecting else { throw LocalStoreError.unavailable }
        let id = operationID
        let page = try await inspector.noteIndexPage(id: noteID, profile: requestedProfile, offset: offset, limit: 50)
        try Task.checkCancellation()
        guard operationID == id, requestedProfile == profile else { throw CancellationError() }
        return page
    }
    func rebuildIndex(noteID: UUID) async -> Bool {
        guard canInspectIndex, edited?.id == noteID, !hasEdits, !isBusy else {
            status = "Сначала сохраните или отмените правки выбранной заметки."; return false
        }
        let id = operationID
        lastSaveSucceeded = false
        save()
        await waitForPendingSave()
        return operationID == id && lastSaveSucceeded
    }
    func activateProfile(_ profile: ProfileID) {
        guard self.profile != profile else { return }
        saveTask?.cancel(); operationID = UUID(); refreshID = UUID(); pageRequestID = UUID()
        isBusy = false; isSearching = false; isLoadingMore = false; totalNoteCount = 0; folders = []; hasMore = false; nextOffset = 0
        self.profile = profile; notes = []; edited = nil; baseline = nil; tagsText = ""; query = ""; selectedFolder = nil
        pendingSelection = nil; pendingImport = nil; confirmNew = false
        Task { await refresh() }
    }
    func refresh() async {
        let refresh = UUID(); refreshID = refresh; pageRequestID = UUID(); isSearching = true; isLoadingMore = false
        defer { if refreshID == refresh { isSearching = false } }
        let id = operationID; let profile = profile; let query = query; let archive = includeArchived; let folder = selectedFolder
        do {
            try Task.checkCancellation()
            let page: NoteLibraryPage
            if let paging = repository as? any NoteLibraryPaging {
                page = try await paging.noteLibraryPage(profile: profile, query: query, includeArchived: archive, folder: folder, offset: 0, limit: 50)
            } else {
                let loaded = try await repository.notes(profile: profile, query: query, includeArchived: archive)
                let counts = Dictionary(grouping: loaded, by: { $0.folder ?? "" }).map { NoteFolderCount(name: $0.key, count: $0.value.count) }.sorted { $0.name < $1.name }
                let filtered = loaded.filter { folder == nil || ($0.folder ?? "") == folder }
                page = NoteLibraryPage(notes: filtered, totalCount: filtered.count, folders: counts, offset: 0, limit: max(1, filtered.count))
            }
            try Task.checkCancellation()
            guard refreshID == refresh, operationID == id, self.query == query, self.includeArchived == archive, selectedFolder == folder else { return }
            notes = page.notes; totalNoteCount = page.totalCount; folders = page.folders
            nextOffset = page.notes.count; hasMore = page.hasNext
        } catch is CancellationError { }
        catch {
            if refreshID == refresh, operationID == id, self.query == query, self.includeArchived == archive, selectedFolder == folder {
                status = "Не удалось прочитать заметки."
            }
        }
    }
    func loadMore() async {
        guard hasMore, !isSearching, !isLoadingMore, let paging = repository as? any NoteLibraryPaging else { return }
        let request = UUID(); pageRequestID = request; isLoadingMore = true
        defer { if pageRequestID == request { isLoadingMore = false } }
        let refresh = refreshID; let operation = operationID; let profile = profile
        let query = query; let archive = includeArchived; let folder = selectedFolder; let offset = nextOffset
        do {
            let page = try await paging.noteLibraryPage(profile: profile, query: query, includeArchived: archive,
                                                      folder: folder, offset: offset, limit: 50)
            try Task.checkCancellation()
            guard pageRequestID == request, refreshID == refresh, operationID == operation,
                  self.query == query, includeArchived == archive, selectedFolder == folder else { return }
            let existing = Set(notes.map(\.id))
            notes.append(contentsOf: page.notes.filter { !existing.contains($0.id) })
            totalNoteCount = page.totalCount; folders = page.folders
            nextOffset = offset + page.notes.count; hasMore = page.hasNext && !page.notes.isEmpty
            status = "Загружено \(notes.count) из \(totalNoteCount) заметок."
        } catch is CancellationError { }
        catch {
            if pageRequestID == request, refreshID == refresh, operationID == operation,
               self.query == query, includeArchived == archive, selectedFolder == folder {
                status = "Не удалось загрузить следующую страницу. Повторите загрузку."
            }
        }
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
        isBusy = true; lastSaveSucceeded = false; status = "Сохранение и локальная индексация…"
        saveTask = Task { [weak self] in
            guard let self else { return }
            defer { if operationID == id { isBusy = false; saveTask = nil } }
            do {
                try await repository.saveNote(note)
                guard operationID == id else { return }
                lastSaveSucceeded = true
                // Не затирать новые правки, сделанные во время записи.
                if edited == snapshot && tagsText == tagSnapshot { applySelection(note) }
                else if edited?.id == note.id { baseline = note }
                status = "Заметка сохранена; локальный индекс обновлён."
                onLibraryChanged?()
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
            onLibraryChanged?()
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
