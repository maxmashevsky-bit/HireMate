import XCTest
import CopilotCore

private actor DelayedNotes: NoteRepository {
    private var gate: CheckedContinuation<Void, Never>?
    private var released = false
    func release() { released = true; gate?.resume(); gate = nil }
    private func wait() async { if !released { await withCheckedContinuation { gate = $0 } } }
    func note(id: UUID, profile: ProfileID) async throws -> Note { throw LocalStoreError.missingRecord }
    func notes(profile: ProfileID, query: String, includeArchived: Bool) async throws -> [Note] { [] }
    func saveNote(_ note: Note) async throws { await wait() }
    func deleteNote(id: UUID, profile: ProfileID) async throws { await wait() }
}

private actor DelayedNoteSearch: NoteRepository {
    private var continuations: [Int: CheckedContinuation<[Note], Error>] = [:]
    private var callCount = 0
    func notes(profile: ProfileID, query: String, includeArchived: Bool) async throws -> [Note] {
        let id = callCount; callCount += 1
        return try await withCheckedThrowingContinuation { continuations[id] = $0 }
    }
    func waitForCalls(_ count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while callCount < count {
            guard ContinuousClock.now < deadline else { throw LocalStoreError.unavailable }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    func complete(_ id: Int, notes: [Note]) { continuations.removeValue(forKey: id)?.resume(returning: notes) }
    func fail(_ id: Int) { continuations.removeValue(forKey: id)?.resume(throwing: LocalStoreError.unavailable) }
    func note(id: UUID, profile: ProfileID) async throws -> Note { throw LocalStoreError.missingRecord }
    func saveNote(_ note: Note) async throws { }
    func deleteNote(id: UUID, profile: ProfileID) async throws { }
}

final class NotesFlowTests: XCTestCase {
    @MainActor
    func testSearchKeepsLatestResultWhenSameQueryReturnsAgainAndPreservesEdits() async throws {
        let repository = DelayedNoteSearch()
        let model = NotesModel(profile: .technical, repository: repository)
        let edited = Note(profileID: .technical, title: "Редактируемая", markdown: "Исходный текст")
        model.select(edited); model.edited?.markdown = "Несохранённый текст"
        model.query = "Горутины"
        let oldest = Task { await model.refresh() }
        try await repository.waitForCalls(1)
        model.query = "Каналы"
        let middle = Task { await model.refresh() }
        try await repository.waitForCalls(2)
        model.query = "Горутины"
        let current = Task { await model.refresh() }
        try await repository.waitForCalls(3)
        let fresh = Note(profileID: .technical, title: "Новый результат")
        await repository.complete(2, notes: [fresh])
        await current.value
        XCTAssertEqual(model.notes, [fresh])
        XCTAssertFalse(model.isSearching)
        await repository.complete(0, notes: [edited])
        await oldest.value
        XCTAssertEqual(model.notes, [fresh])
        let status = model.status
        await repository.fail(1)
        await middle.value
        XCTAssertEqual(model.status, status)
        XCTAssertEqual(model.edited?.markdown, "Несохранённый текст")
        XCTAssertTrue(model.hasEdits)
    }

    @MainActor
    func testCancelledSearchCannotReplaceResultsOrReportFailure() async throws {
        let repository = DelayedNoteSearch()
        let model = NotesModel(profile: .technical, repository: repository)
        let status = model.status
        let task = Task { await model.refresh() }
        try await repository.waitForCalls(1)
        task.cancel()
        await repository.complete(0, notes: [Note(profileID: .technical, title: "Поздний результат")])
        await task.value
        XCTAssertTrue(model.notes.isEmpty)
        XCTAssertFalse(model.isSearching)
        XCTAssertEqual(model.status, status)
    }

    @MainActor
    func testLocalSearchFindsTitleAndBodyWithoutAIConsentOrCrossingProfiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = GRDBMeetingRepository(directory: directory)
        let titleMatch = Note(profileID: .technical, title: "Горутины")
        let bodyMatch = Note(profileID: .technical, title: "Планировщик", markdown: "Горутины и каналы")
        let foreign = Note(profileID: .hr, title: "Горутины")
        for note in [titleMatch, bodyMatch, foreign] { try await repository.saveNote(note) }
        let model = NotesModel(profile: .technical, repository: repository)
        model.query = "Горутины"
        await model.refresh()
        XCTAssertEqual(Set(model.notes.map(\.id)), Set([titleMatch.id, bodyMatch.id]))
        XCTAssertTrue(model.notes.allSatisfy { !$0.allowAI })
        model.query = "Несуществующее"
        await model.refresh()
        XCTAssertTrue(model.notes.isEmpty)
        model.query = ""
        await model.refresh()
        XCTAssertEqual(model.notes.count, 2)
    }

    func testFolderSurvivesArchiveRoundTrip() throws {
        var note = Note(profileID: .technical, title: "Алгоритмы", markdown: "Текст")
        note.folder = "Подготовка"
        let restored = try NoteArchive.decode(try NoteArchive(note: note).encode()).importedNote()
        XCTAssertEqual(restored.folder, "Подготовка")
    }

    @MainActor
    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw LocalStoreError.unavailable }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor
    func testLateSaveDoesNotReplaceOtherNotesUndoBaseline() async throws {
        let repository = DelayedNotes()
        let model = NotesModel(profile: .technical, repository: repository)
        let first = Note(profileID: .technical, title: "Первая", markdown: "Исходный текст")
        let second = Note(profileID: .technical, title: "Вторая", markdown: "Другой текст")
        model.select(first)
        model.edited?.markdown = "Изменения первой"
        model.save()
        model.select(second)
        model.confirmSelection()
        await repository.release()
        try await waitUntil { !model.isBusy }
        model.edited?.markdown = "Изменения второй"
        model.cancelEdits()
        XCTAssertEqual(model.edited, second)
    }

    @MainActor
    func testDeleteDoesNotClearAnotherOpenNote() async throws {
        let repository = DelayedNotes()
        let model = NotesModel(profile: .technical, repository: repository)
        let first = Note(profileID: .technical, title: "Первая")
        let second = Note(profileID: .technical, title: "Вторая")
        model.select(first)
        let deletion = Task { await model.deleteSelected() }
        try await waitUntil { model.isBusy }
        model.select(second)
        await repository.release()
        await deletion.value
        XCTAssertEqual(model.edited, second)
        XCTAssertFalse(model.isBusy)
    }

    func testArchiveRoundTripDoesNotTransferAIConsentOrPath() throws {
        var note = Note(profileID: .hr, title: "Опыт", markdown: "Подтверждённый факт")
        note.tags = ["Go", "проект"]; note.isPinned = true; note.allowAI = true
        note.sourcePath = "/private/user/document.md"
        let data = try NoteArchive(note: note).encode()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("/private/user"))
        XCTAssertFalse(text.contains("allowAI"))
        let imported = try NoteArchive.decode(data).importedNote()
        XCTAssertNotEqual(imported.id, note.id)
        XCTAssertEqual(imported.markdown, note.markdown)
        XCTAssertEqual(imported.tags, note.tags)
        XCTAssertTrue(imported.isPinned)
        XCTAssertFalse(imported.allowAI)
        XCTAssertNil(imported.sourcePath)
    }

    func testArchiveRejectsModifiedContentAndUnsupportedVersion() throws {
        let data = try NoteArchive(note: Note(profileID: .hr, markdown: "Текст")).encode()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["markdown"] = "Изменённый текст"
        XCTAssertThrowsError(try NoteArchive.decode(JSONSerialization.data(withJSONObject: json)))
        json["markdown"] = "Текст"; json["version"] = 999
        XCTAssertThrowsError(try NoteArchive.decode(JSONSerialization.data(withJSONObject: json)))
    }
}
