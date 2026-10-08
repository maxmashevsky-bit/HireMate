import XCTest
import CopilotCore
import GRDB

final class NoteIndexFlowTests: XCTestCase {
    @MainActor
    func testRebuildReplacesLegacyTinyChunksAndKeepsSavedTextAndConsent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBMeetingRepository(directory: root)
        let paragraphs = (0..<50).map { "Абзац \($0)" }
        let note = Note(profileID: .technical, title: "Старый индекс", markdown: paragraphs.joined(separator: "\n\n"))
        try await repository.saveNote(note)
        try installLegacyChunks(root, note: note, paragraphs: paragraphs)
        let before = try await repository.noteIndexPage(id: note.id, profile: .technical, offset: 0, limit: 100)
        XCTAssertEqual(before.totalCount, 50)
        let saved = try await repository.note(id: note.id, profile: .technical)
        let model = NotesModel(profile: .technical, repository: repository)
        model.select(saved)
        let rebuilt = await model.rebuildIndex(noteID: note.id)
        XCTAssertTrue(rebuilt)
        let after = try await repository.noteIndexPage(id: note.id, profile: .technical, offset: 0, limit: 100)
        XCTAssertEqual(after.totalCount, 1)
        XCTAssertEqual(after.note.markdown, note.markdown)
        XCTAssertFalse(after.note.allowAI)
        XCTAssertEqual(after.note.id, note.id)
        XCTAssertFalse(model.hasEdits)
    }

    @MainActor
    func testRebuildRejectsUnsavedAndDirtyNotesWithoutWritingThem() async throws {
        let note = Note(profileID: .technical, title: "Сохранённая", markdown: "Текст")
        let repository = DelayedNoteIndexStore(note: note)
        let model = NotesModel(profile: .technical, repository: repository)
        model.newDraft()
        let draftRebuild = await model.rebuildIndex(noteID: try XCTUnwrap(model.edited?.id))
        XCTAssertFalse(draftRebuild)
        model.cancelEdits(); model.select(note)
        model.edited?.markdown = "Несохранённые правки"
        let dirtyRebuild = await model.rebuildIndex(noteID: note.id)
        XCTAssertFalse(dirtyRebuild)
        XCTAssertEqual(model.edited?.markdown, "Несохранённые правки")
        let saves = await repository.saves
        XCTAssertEqual(saves, 0)
    }

    private func installLegacyChunks(_ root: URL, note: Note, paragraphs: [String]) throws {
        let queue = try DatabaseQueue(path: root.appendingPathComponent("copilot.sqlite").path)
        defer { try? queue.close() }
        try queue.write { db in
            try db.execute(sql: "DELETE FROM note_fts WHERE noteID=?", arguments: [note.id.uuidString])
            try db.execute(sql: "DELETE FROM note_chunks WHERE noteID=?", arguments: [note.id.uuidString])
            for (index, text) in paragraphs.enumerated() {
                let fragment = NoteFragment(note: note, index: index, text: text)
                try db.execute(sql: "INSERT INTO note_chunks(id,noteID,payload) VALUES (?,?,?)", arguments: [fragment.id, note.id.uuidString, try JSONEncoder().encode(fragment)])
                try db.execute(sql: "INSERT INTO note_fts(chunkID,noteID,title,body) VALUES (?,?,?,?)", arguments: [fragment.id, note.id.uuidString, note.title, fragment.text])
            }
        }
    }

    @MainActor
    func testInspectingSavedVersionDoesNotSaveOrReplaceCurrentDraft() async throws {
        let note = Note(profileID: .technical, title: "Сохранённая", markdown: "Старый текст")
        let repository = DelayedNoteIndexStore(note: note)
        let model = NotesModel(profile: .technical, repository: repository)
        model.newDraft()
        XCTAssertFalse(model.canInspectIndex)
        model.cancelEdits()
        model.select(note)
        XCTAssertTrue(model.canInspectIndex)
        model.edited?.markdown = "Несохранённые правки"
        let page = try await model.indexPage(noteID: note.id, profile: .technical, offset: 0)
        XCTAssertEqual(page.note.markdown, "Старый текст")
        XCTAssertEqual(model.edited?.markdown, "Несохранённые правки")
        XCTAssertTrue(model.hasEdits)
        let saves = await repository.saves
        XCTAssertEqual(saves, 0)
        do {
            _ = try await model.indexPage(noteID: note.id, profile: .hr, offset: 0)
            XCTFail("Нельзя читать индекс другого активного профиля")
        } catch LocalStoreError.unavailable { }
    }

    @MainActor
    func testLateIndexResponseIsCancelledAfterProfileChangesAwayAndBack() async throws {
        let note = Note(profileID: .technical, title: "Сохранённая", markdown: "Текст")
        let repository = DelayedNoteIndexStore(note: note)
        await repository.pauseNextPage()
        let model = NotesModel(profile: .technical, repository: repository)
        let read = Task { try await model.indexPage(noteID: note.id, profile: .technical, offset: 0) }
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await repository.isPaused) {
            guard ContinuousClock.now < deadline else { throw LocalStoreError.unavailable }
            try await Task.sleep(for: .milliseconds(5))
        }
        model.activateProfile(.hr)
        model.activateProfile(.technical)
        await repository.release()
        do {
            _ = try await read.value
            XCTFail("Поздний ответ не должен попасть в новый сеанс профиля")
        } catch is CancellationError { }
    }
}

private actor DelayedNoteIndexStore: NoteRepository, NoteIndexInspecting {
    let stored: Note
    private var holdPage = false
    private var gate: CheckedContinuation<Void, Never>?
    private(set) var saves = 0
    var isPaused: Bool { gate != nil }
    init(note: Note) { stored = note }
    func pauseNextPage() { holdPage = true }
    func release() { gate?.resume(); gate = nil }
    func note(id: UUID, profile: ProfileID) async throws -> Note { stored }
    func notes(profile: ProfileID, query: String, includeArchived: Bool) async throws -> [Note] { [] }
    func saveNote(_ note: Note) async throws { saves += 1 }
    func deleteNote(id: UUID, profile: ProfileID) async throws { }
    func noteIndexPage(id: UUID, profile: ProfileID, offset: Int, limit: Int) async throws -> NoteIndexPage {
        if holdPage { holdPage = false; await withCheckedContinuation { gate = $0 } }
        return NoteIndexPage(note: stored, fragments: NoteChunker.chunks(stored), totalCount: 1, offset: offset, limit: limit)
    }
}
