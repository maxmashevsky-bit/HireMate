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

final class NotesFlowTests: XCTestCase {
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
