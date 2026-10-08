import XCTest
import GRDB
import CopilotCore

final class NoteLibraryTests: XCTestCase {
    func testPagesBeyondOldCapHaveStableOrderFullFolderCountsAndScopedSearch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBMeetingRepository(directory: root)
        var expected: [Note] = []
        for index in 0...600 {
            var note = Note(profileID: .technical, title: "Документ \(index)", markdown: index.isMultiple(of: 3) ? "Горутины и каналы" : "План подготовки")
            note.folder = index.isMultiple(of: 2) ? "Подготовка" : nil
            note.isPinned = index.isMultiple(of: 100)
            try await repository.saveNote(note); expected.append(note)
        }
        var archived = Note(profileID: .technical, title: "Архив", markdown: "Горутины")
        archived.isArchived = true
        try await repository.saveNote(archived)
        try await repository.saveNote(Note(profileID: .hr, title: "Чужая", markdown: "Горутины"))
        try setEqualSortDates(root)
        var all: [Note] = []
        for offset in stride(from: 0, through: 600, by: 100) {
            let page = try await repository.noteLibraryPage(profile: .technical, query: "", includeArchived: false, folder: nil, offset: offset, limit: 100)
            XCTAssertEqual(page.totalCount, 601)
            XCTAssertEqual(page.folders, [NoteFolderCount(name: "", count: 300), NoteFolderCount(name: "Подготовка", count: 301)])
            XCTAssertEqual(page.hasNext, offset < 600)
            all += page.notes
        }
        let ordered = expected.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.id.uuidString < $1.id.uuidString
        }
        XCTAssertEqual(all.map(\.id), ordered.map(\.id))
        XCTAssertEqual(Set(all.map(\.id)).count, 601)
        let folder = try await repository.noteLibraryPage(profile: .technical, query: "", includeArchived: false, folder: "Подготовка", offset: 300, limit: 50)
        XCTAssertEqual(folder.notes.count, 1)
        XCTAssertEqual(folder.totalCount, 301)
        XCTAssertEqual(folder.folders.reduce(0) { $0 + $1.count }, 601)
        let search = try await repository.noteLibraryPage(profile: .technical, query: "Горутины", includeArchived: false, folder: nil, offset: 200, limit: 50)
        XCTAssertEqual(search.totalCount, 201)
        XCTAssertEqual(search.notes.count, 1)
        XCTAssertFalse(search.notes[0].allowAI)
        let withArchive = try await repository.noteLibraryPage(profile: .technical, query: "Горутины", includeArchived: true, folder: nil, offset: 0, limit: 50)
        XCTAssertEqual(withArchive.totalCount, 202)
        let unfiled = try await repository.noteLibraryPage(profile: .technical, query: "", includeArchived: false, folder: "", offset: 0, limit: 50)
        XCTAssertEqual(unfiled.totalCount, 300)
        XCTAssertTrue(unfiled.notes.allSatisfy { $0.folder == nil })
    }

    func testInvalidOrNonSearchableQueryDoesNotSilentlyReturnWholeLibrary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBMeetingRepository(directory: root)
        try await repository.saveNote(Note(profileID: .technical, title: "Заметка"))
        for query in ["а", "!!!", "\" OR * --"] {
            let page = try await repository.noteLibraryPage(profile: .technical, query: query, includeArchived: false, folder: nil, offset: 0, limit: 50)
            XCTAssertTrue(page.notes.isEmpty)
            XCTAssertEqual(page.totalCount, 0)
        }
        for (offset, limit, query) in [(-1, 50, ""), (Int.max, 50, ""), (0, 101, ""), (0, 0, ""), (0, 50, String(repeating: "а", count: 4097))] {
            do {
                _ = try await repository.noteLibraryPage(profile: .technical, query: query, includeArchived: false, folder: nil, offset: offset, limit: limit)
                XCTFail("Некорректные параметры должны быть отклонены")
            } catch LocalStoreError.invalidData { }
        }
    }

    func testStoredMarkdownSubsetSurvivesReloadAndHasEquivalentParsedBlocks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = "# Заголовок\n\n**жирный** *курсив* ~~зачёркнутый~~ `код`\n\n- первый\n- второй\n\n2. пункт\n\n> цитата\n\n---\n\n| Имя | Значение |\n| --- | ---: |\n| a\\|b | 42 |\n\n```go\nfunc main() {}\n```"
        let note = Note(profileID: .hr, title: "Markdown", markdown: source)
        let repository = GRDBMeetingRepository(directory: root)
        try await repository.saveNote(note)
        let reopened = GRDBMeetingRepository(directory: root)
        let stored = try await reopened.note(id: note.id, profile: .hr)
        XCTAssertEqual(stored.markdown, source)
        XCTAssertEqual(AnswerDocument.blocks(stored.markdown), AnswerDocument.blocks(source))
        XCTAssertEqual(stored.contentHash, Note.hash(source))
    }

    func testCorruptNoteIdentityProfileAndHashAreRejectedByAllReadPathsWithoutMutation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBMeetingRepository(directory: root)
        let original = Note(profileID: .technical, title: "Целостность", markdown: "Исходный текст")
        try await repository.saveNote(original)
        var staleHash = original; staleHash.markdown = "Повреждённый текст"
        let wrongIdentity = Note(profileID: .technical, title: "Другая запись")
        let foreign = Note(profileID: .hr, title: "Чужой профиль")
        for damaged in [staleHash, wrongIdentity, foreign] {
            let payload = try JSONEncoder().encode(damaged)
            try replacePayload(root, id: original.id, payload: payload)
            do {
                _ = try await repository.note(id: original.id, profile: .technical)
                XCTFail("Single-note read принял повреждение")
            } catch LocalStoreError.invalidData { }
            do {
                _ = try await repository.notes(profile: .technical, query: "", includeArchived: false)
                XCTFail("Legacy list принял повреждение")
            } catch LocalStoreError.invalidData { }
            do {
                _ = try await repository.noteLibraryPage(profile: .technical, query: "", includeArchived: false, folder: nil, offset: 0, limit: 50)
                XCTFail("Paged list принял повреждение")
            } catch LocalStoreError.invalidData { }
            XCTAssertEqual(try storedPayload(root, id: original.id), payload)
        }
    }

    private func replacePayload(_ root: URL, id: UUID, payload: Data) throws {
        let queue = try DatabaseQueue(path: root.appendingPathComponent("copilot.sqlite").path)
        defer { try? queue.close() }
        try queue.write { try $0.execute(sql: "UPDATE notes SET payload=? WHERE id=?", arguments: [payload,id.uuidString]) }
    }
    private func storedPayload(_ root: URL, id: UUID) throws -> Data? {
        let queue = try DatabaseQueue(path: root.appendingPathComponent("copilot.sqlite").path)
        defer { try? queue.close() }
        return try queue.read { try Data.fetchOne($0, sql: "SELECT payload FROM notes WHERE id=?", arguments: [id.uuidString]) }
    }

    private func setEqualSortDates(_ root: URL) throws {
        let queue = try DatabaseQueue(path: root.appendingPathComponent("copilot.sqlite").path)
        defer { try? queue.close() }
        try queue.write { try $0.execute(sql: "UPDATE notes SET updatedAt=1234") }
    }
}
