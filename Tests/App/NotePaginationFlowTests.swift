import XCTest
import CopilotCore

private actor DelayedNotePages: NoteRepository, NoteLibraryPaging {
    private var calls = 0
    private var pending: [Int: CheckedContinuation<NoteLibraryPage, Error>] = [:]
    func noteLibraryPage(profile: ProfileID, query: String, includeArchived: Bool, folder: String?, offset: Int, limit: Int) async throws -> NoteLibraryPage {
        let call = calls; calls += 1
        return try await withCheckedThrowingContinuation { pending[call] = $0 }
    }
    func waitForCalls(_ count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while calls < count {
            guard ContinuousClock.now < deadline else { throw LocalStoreError.unavailable }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    func complete(_ call: Int, page: NoteLibraryPage) { pending.removeValue(forKey: call)?.resume(returning: page) }
    func fail(_ call: Int) { pending.removeValue(forKey: call)?.resume(throwing: LocalStoreError.unavailable) }
    func note(id: UUID, profile: ProfileID) async throws -> Note { throw LocalStoreError.missingRecord }
    func notes(profile: ProfileID, query: String, includeArchived: Bool) async throws -> [Note] { XCTFail("Paging store не должен запрашиваться старым capped API"); return [] }
    func saveNote(_ note: Note) async throws { }
    func deleteNote(id: UUID, profile: ProfileID) async throws { }
}

final class NotePaginationFlowTests: XCTestCase {
    @MainActor
    func testLoadingFurtherPagesAndFolderFilterPreservesUnsavedEditor() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBMeetingRepository(directory: root)
        var first: Note?
        for index in 0..<56 {
            var note = Note(profileID: .technical, title: "Заметка \(index)")
            if index < 2 { note.folder = "Старая папка" }
            try await repository.saveNote(note)
            if index == 0 { first = note }
        }
        let model = NotesModel(profile: .technical, repository: repository)
        model.select(try XCTUnwrap(first)); model.edited?.markdown = "Не потерять черновик"
        await model.refresh()
        XCTAssertEqual(model.notes.count, 50)
        XCTAssertEqual(model.totalNoteCount, 56)
        XCTAssertTrue(model.hasMore)
        XCTAssertEqual(model.folders.first { $0.name == "Старая папка" }?.count, 2)
        XCTAssertFalse(model.notes.contains { $0.folder == "Старая папка" })
        await model.loadMore()
        XCTAssertEqual(model.notes.count, 56)
        XCTAssertFalse(model.hasMore)
        model.selectedFolder = "Старая папка"
        await model.refresh()
        XCTAssertEqual(model.notes.count, 2)
        XCTAssertEqual(model.totalNoteCount, 2)
        XCTAssertEqual(model.edited?.markdown, "Не потерять черновик")
        XCTAssertTrue(model.hasEdits)
    }

    @MainActor
    func testLatePageCannotAppendAfterSearchABAOrChangeNewCount() async throws {
        let repository = DelayedNotePages()
        let model = NotesModel(profile: .technical, repository: repository)
        model.query = "Первый"
        let initial = Task { await model.refresh() }
        try await repository.waitForCalls(1)
        let first = makePage(profile: .technical, count: 50, total: 60, offset: 0)
        await repository.complete(0, page: first); await initial.value
        let oldPage = Task { await model.loadMore() }
        try await repository.waitForCalls(2)
        model.query = "Второй"
        let intermediate = Task { await model.refresh() }
        try await repository.waitForCalls(3)
        model.query = "Первый"
        let newest = Task { await model.refresh() }
        try await repository.waitForCalls(4)
        let current = makePage(profile: .technical, count: 2, total: 2, offset: 0)
        await repository.complete(3, page: current); await newest.value
        let status = model.status
        await repository.complete(1, page: makePage(profile: .technical, count: 10, total: 60, offset: 50)); await oldPage.value
        await repository.fail(2); await intermediate.value
        XCTAssertEqual(model.notes, current.notes)
        XCTAssertEqual(model.totalNoteCount, 2)
        XCTAssertFalse(model.hasMore)
        XCTAssertFalse(model.isLoadingMore)
        XCTAssertEqual(model.status, status)
    }

    @MainActor
    func testPageFailureKeepsLoadedNotesAndAllowsRetryWithoutParallelDuplicates() async throws {
        let repository = DelayedNotePages()
        let model = NotesModel(profile: .technical, repository: repository)
        let initial = Task { await model.refresh() }
        try await repository.waitForCalls(1)
        let first = makePage(profile: .technical, count: 50, total: 60, offset: 0)
        await repository.complete(0, page: first); await initial.value
        let failed = Task { await model.loadMore() }
        try await repository.waitForCalls(2)
        await model.loadMore()
        await repository.fail(1); await failed.value
        XCTAssertEqual(model.notes, first.notes)
        XCTAssertTrue(model.hasMore)
        XCTAssertFalse(model.isLoadingMore)
        XCTAssertTrue(model.status.contains("Повторите"))
        let retry = Task { await model.loadMore() }
        try await repository.waitForCalls(3)
        let last = makePage(profile: .technical, count: 10, total: 60, offset: 50)
        await repository.complete(2, page: last); await retry.value
        XCTAssertEqual(model.notes, first.notes + last.notes)
        XCTAssertFalse(model.hasMore)
    }

    @MainActor
    func testProfileSwitchClearsPagingAndRejectsLateForeignPage() async throws {
        let repository = DelayedNotePages()
        let model = NotesModel(profile: .technical, repository: repository)
        let old = Task { await model.refresh() }
        try await repository.waitForCalls(1)
        model.activateProfile(.hr)
        try await repository.waitForCalls(2)
        XCTAssertTrue(model.notes.isEmpty)
        XCTAssertEqual(model.totalNoteCount, 0)
        let current = makePage(profile: .hr, count: 1, total: 1, offset: 0)
        await repository.complete(1, page: current)
        await repository.complete(0, page: makePage(profile: .technical, count: 50, total: 80, offset: 0))
        await old.value
        let deadline = ContinuousClock.now + .seconds(3)
        while model.isSearching {
            guard ContinuousClock.now < deadline else { throw LocalStoreError.unavailable }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.notes, current.notes)
        XCTAssertEqual(model.totalNoteCount, 1)
        XCTAssertFalse(model.hasMore)
    }

    private func makePage(profile: ProfileID, count: Int, total: Int, offset: Int) -> NoteLibraryPage {
        NoteLibraryPage(notes: (0..<count).map { Note(profileID: profile, title: "Страница \(offset + $0)") },
                        totalCount: total, folders: [NoteFolderCount(name: "", count: total)], offset: offset, limit: 50)
    }
}
