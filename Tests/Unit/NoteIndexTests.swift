import XCTest
import GRDB
import CopilotCore

final class NoteIndexTests: XCTestCase {
    func testReadsStoredPagesWithoutAIConsentAndKeepsProfileScope() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBMeetingRepository(directory: root)
        let note = Note(profileID: .technical, title: "Страницы", markdown: (0..<120).map { "# Раздел \($0)\nТекст фрагмента \($0) " + String(repeating: "а", count: 700) }.joined(separator: "\n\n"))
        try await repository.saveNote(note)
        let first = try await repository.noteIndexPage(id: note.id, profile: .technical, offset: 0, limit: 50)
        let second = try await repository.noteIndexPage(id: note.id, profile: .technical, offset: 50, limit: 50)
        let last = try await repository.noteIndexPage(id: note.id, profile: .technical, offset: 100, limit: 50)
        XCTAssertEqual(first.totalCount, 120)
        XCTAssertEqual(first.fragments.map(\.index), Array(0..<50))
        XCTAssertEqual(second.fragments.map(\.index), Array(50..<100))
        XCTAssertEqual(last.fragments.map(\.index), Array(100..<120))
        XCTAssertTrue(first.hasNext)
        XCTAssertFalse(last.hasNext)
        XCTAssertFalse(first.note.allowAI)
        XCTAssertTrue(first.fragments.allSatisfy { $0.sourceHash == note.contentHash && $0.noteID == note.id })
        let rag = try await repository.retrieve(query: "фрагмента", profile: .technical, tags: [], limit: 5)
        XCTAssertTrue(rag.isEmpty)
        do {
            _ = try await repository.noteIndexPage(id: note.id, profile: .hr, offset: 0, limit: 50)
            XCTFail("Чужой профиль не видит индекс")
        } catch LocalStoreError.missingRecord { }
    }

    func testIndexReflectsReplacementAndDeletedNotesAndRejectsUnboundedRequests() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBMeetingRepository(directory: root)
        var note = Note(profileID: .hr, title: "Первая", markdown: "Старый текст")
        try await repository.saveNote(note)
        let before = try await repository.noteIndexPage(id: note.id, profile: .hr, offset: 0, limit: 50)
        note.title = "Изменённая"; note.markdown = "Новый текст"; note.tags = ["Опыт"]
        try await repository.saveNote(note)
        let after = try await repository.noteIndexPage(id: note.id, profile: .hr, offset: 0, limit: 50)
        XCTAssertEqual(after.totalCount, 1)
        XCTAssertEqual(after.fragments.first?.text, "Новый текст")
        XCTAssertEqual(after.fragments.first?.title, "Изменённая")
        XCTAssertEqual(after.fragments.first?.tags, ["Опыт"])
        XCTAssertNotEqual(before.fragments.first?.id, after.fragments.first?.id)
        for (offset, limit) in [(-1, 50), (0, 0), (0, 101), (Int.max, 50)] {
            do {
                _ = try await repository.noteIndexPage(id: note.id, profile: .hr, offset: offset, limit: limit)
                XCTFail("Некорректная страница должна быть отклонена")
            } catch LocalStoreError.invalidData { }
        }
        try await repository.deleteNote(id: note.id, profile: .hr)
        do {
            _ = try await repository.noteIndexPage(id: note.id, profile: .hr, offset: 0, limit: 50)
            XCTFail("Удалённая заметка не видна")
        } catch LocalStoreError.missingRecord { }
    }

    func testCorruptOrStaleStoredFragmentIsReportedWithoutChangingNote() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBMeetingRepository(directory: root)
        let note = Note(profileID: .technical, title: "Индекс", markdown: "Текст")
        try await repository.saveNote(note)
        let page = try await repository.noteIndexPage(id: note.id, profile: .technical, offset: 0, limit: 50)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(page.fragments[0])) as? [String: Any])
        json["sourceHash"] = "устаревшая версия"
        let payload = try JSONSerialization.data(withJSONObject: json)
        try replaceFragment(root, id: page.fragments[0].id, payload: payload)
        do {
            _ = try await repository.noteIndexPage(id: note.id, profile: .technical, offset: 0, limit: 50)
            XCTFail("Устаревший индекс должен быть явно отклонён")
        } catch LocalStoreError.invalidData { }
        let stored = try await repository.note(id: note.id, profile: .technical)
        XCTAssertEqual(stored.markdown, note.markdown)
    }
    private func replaceFragment(_ root: URL, id: String, payload: Data) throws {
        let queue = try DatabaseQueue(path: root.appendingPathComponent("copilot.sqlite").path)
        defer { try? queue.close() }
        try queue.write { db in try db.execute(sql: "UPDATE note_chunks SET payload=? WHERE id=?", arguments: [payload, id]) }
    }
}
