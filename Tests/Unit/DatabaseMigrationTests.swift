import XCTest
import GRDB
import CopilotCore

final class DatabaseMigrationTests: XCTestCase {
    func testV1UpgradePreservesProfilesMeetingsAndMessagesAndAddsNewStores() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try makeV1Fixture(root)
        let repository = GRDBMeetingRepository(directory: root)
        let profiles = try await repository.profiles()
        XCTAssertEqual(profiles.first { $0.id == .technical }?.name, "Старый профиль")
        let meetings = try await repository.meetings(profile: .technical)
        XCTAssertEqual(meetings.map(\.id), [fixture.meeting.id])
        let messages = try await repository.messages(subchatID: fixture.chat.id, meetingID: fixture.meeting.id)
        XCTAssertEqual(messages.map(\.content), ["Вопрос из версии 1"])
        let initiallyEmpty = try await repository.transcriptTimeline(meetingID: fixture.meeting.id, profile: .technical)
        XCTAssertTrue(initiallyEmpty.entries.isEmpty)
        var timeline = TranscriptTimeline()
        timeline.append(TranscriptResult(segment: AudioSegment(source: .system, startedAt: 1, samples: [0.1], reason: "Тест"),
                                         text: "Новая расшифровка", isDemo: false))
        try await repository.saveTranscriptTimeline(timeline, meetingID: fixture.meeting.id, profile: .technical)
        let note = Note(profileID: .technical, title: "После обновления", markdown: "Локальный поиск")
        try await repository.saveNote(note)
        let notes = try await repository.notes(profile: .technical, query: "", includeArchived: false)
        XCTAssertEqual(notes.map(\.id), [note.id])
        let stages = try await repository.vacancyStages()
        XCTAssertEqual(stages.count, VacancyStage.standard.count)

        let reopened = GRDBMeetingRepository(directory: root)
        let restored = try await reopened.transcriptTimeline(meetingID: fixture.meeting.id, profile: .technical)
        XCTAssertEqual(restored, timeline)
        let again = try await reopened.messages(subchatID: fixture.chat.id, meetingID: fixture.meeting.id)
        XCTAssertEqual(again.map(\.content), messages.map(\.content))
        XCTAssertEqual(try migrationIDs(root), ["v1_profiles_and_meetings", "v2_notes_fts", "v3_vacancy_tracker", "v4_meeting_transcripts", "v5_note_library_paging"])
    }

    func testCorruptTranscriptDoesNotOverwriteMeetingOrBecomeUsableHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try makeV1Fixture(root)
        let repository = GRDBMeetingRepository(directory: root)
        _ = try await repository.profiles()
        try writeCorruptTranscript(root, meetingID: fixture.meeting.id)
        do {
            _ = try await repository.transcriptTimeline(meetingID: fixture.meeting.id, profile: .technical)
            XCTFail("Повреждённую историю нельзя считать пустой и перезаписать")
        } catch LocalStoreError.invalidData { }
        let messages = try await repository.messages(subchatID: fixture.chat.id, meetingID: fixture.meeting.id)
        XCTAssertEqual(messages.map(\.content), ["Вопрос из версии 1"])
        let meetings = try await repository.meetings(profile: .technical)
        XCTAssertEqual(meetings.map(\.id), [fixture.meeting.id])
    }

    func testV4FolderMetadataUpgradePreservesPayloadAndFTSRowsWithoutReindexing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeV1Fixture(root)
        var note = Note(profileID: .technical, title: "Старая заметка", markdown: "Горутины из старого индекса")
        note.folder = "Моя папка"; note.tags = ["Go"]; note.allowAI = true; note.isPinned = true
        let payload = try JSONEncoder().encode(note)
        let fragment = NoteFragment(note: note, index: 0, text: note.markdown)
        try makeV4NoteStore(root, note: note, payload: payload, fragment: fragment)
        let repository = GRDBMeetingRepository(directory: root)
        let page = try await repository.noteLibraryPage(profile: .technical, query: "Горутины", includeArchived: false, folder: "Моя папка", offset: 0, limit: 50)
        XCTAssertEqual(page.notes, [note])
        XCTAssertEqual(page.folders, [NoteFolderCount(name: "Моя папка", count: 1)])
        let index = try await repository.noteIndexPage(id: note.id, profile: .technical, offset: 0, limit: 50)
        XCTAssertEqual(index.fragments, [fragment])
        let queue = try DatabaseQueue(path: root.appendingPathComponent("copilot.sqlite").path)
        defer { try? queue.close() }
        let noteID = note.id.uuidString
        let after = try await queue.read { try Data.fetchOne($0, sql: "SELECT payload FROM notes WHERE id=?", arguments: [noteID]) }
        XCTAssertEqual(after, payload)
        let reopened = GRDBMeetingRepository(directory: root)
        let again = try await reopened.noteLibraryPage(profile: .technical, query: "", includeArchived: false, folder: "Моя папка", offset: 0, limit: 50)
        XCTAssertEqual(again.notes, [note])
    }

    private func makeV4NoteStore(_ root: URL, note: Note, payload: Data, fragment: NoteFragment) throws {
        let queue = try DatabaseQueue(path: root.appendingPathComponent("copilot.sqlite").path)
        defer { try? queue.close() }
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO grdb_migrations VALUES ('v2_notes_fts'),('v3_vacancy_tracker'),('v4_meeting_transcripts');
                CREATE TABLE notes (id TEXT PRIMARY KEY,profileID TEXT NOT NULL,isPinned BOOLEAN NOT NULL,isArchived BOOLEAN NOT NULL,allowAI BOOLEAN NOT NULL,updatedAt DOUBLE NOT NULL,payload BLOB NOT NULL);
                CREATE INDEX notes_on_profileID ON notes(profileID);
                CREATE TABLE note_chunks (id TEXT PRIMARY KEY,noteID TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,payload BLOB NOT NULL);
                CREATE INDEX note_chunks_on_noteID ON note_chunks(noteID);
                CREATE VIRTUAL TABLE note_fts USING fts5(chunkID UNINDEXED,noteID UNINDEXED,title,body,tokenize='unicode61');
                CREATE TABLE vacancy_stages (id TEXT PRIMARY KEY,position INTEGER NOT NULL,payload BLOB NOT NULL);
                CREATE TABLE vacancies (id TEXT PRIMARY KEY,stageID TEXT NOT NULL REFERENCES vacancy_stages(id),isArchived BOOLEAN NOT NULL,updatedAt DOUBLE NOT NULL,payload BLOB NOT NULL);
                CREATE TABLE vacancy_transitions (id TEXT PRIMARY KEY,vacancyID TEXT NOT NULL REFERENCES vacancies(id) ON DELETE CASCADE,happenedAt DOUBLE NOT NULL,payload BLOB NOT NULL);
                CREATE TABLE meeting_transcripts (meetingID TEXT PRIMARY KEY REFERENCES meetings(id) ON DELETE CASCADE,payload BLOB NOT NULL);
                """)
            try db.execute(sql: "INSERT INTO notes VALUES (?,?,?,?,?,?,?)", arguments: [note.id.uuidString,note.profileID.rawValue,note.isPinned,note.isArchived,note.allowAI,note.updatedAt.timeIntervalSince1970,payload])
            try db.execute(sql: "INSERT INTO note_chunks VALUES (?,?,?)", arguments: [fragment.id,note.id.uuidString,try JSONEncoder().encode(fragment)])
            try db.execute(sql: "INSERT INTO note_fts VALUES (?,?,?,?)", arguments: [fragment.id,note.id.uuidString,note.title,fragment.text])
        }
    }

    // Историческая схема v1: fixture не создаётся через текущий migrator.
    private func makeV1Fixture(_ root: URL) throws -> (meeting: Meeting, chat: Subchat) {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: root.appendingPathComponent("copilot.sqlite").path)
        defer { try? queue.close() }
        let meeting = Meeting(profileID: .technical, title: "Старая встреча", isEphemeral: false)
        let chat = Subchat(meetingID: meeting.id, title: "Первый поддиалог")
        let message = ChatMessage(subchatID: chat.id, role: .user, content: "Вопрос из версии 1")
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES ('v1_profiles_and_meetings');
                CREATE TABLE context_profiles (id TEXT PRIMARY KEY, payload BLOB NOT NULL);
                CREATE TABLE meetings (id TEXT PRIMARY KEY, profileID TEXT NOT NULL, createdAt DOUBLE NOT NULL, payload BLOB NOT NULL);
                CREATE INDEX meetings_on_profileID ON meetings(profileID);
                CREATE TABLE subchats (id TEXT PRIMARY KEY, meetingID TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE, createdAt DOUBLE NOT NULL, payload BLOB NOT NULL);
                CREATE INDEX subchats_on_meetingID ON subchats(meetingID);
                CREATE TABLE messages (id TEXT PRIMARY KEY, subchatID TEXT NOT NULL REFERENCES subchats(id) ON DELETE CASCADE, createdAt DOUBLE NOT NULL, payload BLOB NOT NULL);
                CREATE INDEX messages_on_subchatID ON messages(subchatID);
                """)
            for id in ProfileID.allCases {
                var profile = ContextProfile(id: id)
                if id == .technical { profile.name = "Старый профиль" }
                try db.execute(sql: "INSERT INTO context_profiles(id,payload) VALUES (?,?)",
                               arguments: [id.rawValue, try JSONEncoder().encode(profile)])
            }
            try db.execute(sql: "INSERT INTO meetings(id,profileID,createdAt,payload) VALUES (?,?,?,?)",
                           arguments: [meeting.id.uuidString, meeting.profileID.rawValue, meeting.createdAt.timeIntervalSince1970, try JSONEncoder().encode(meeting)])
            try db.execute(sql: "INSERT INTO subchats(id,meetingID,createdAt,payload) VALUES (?,?,?,?)",
                           arguments: [chat.id.uuidString, meeting.id.uuidString, chat.createdAt.timeIntervalSince1970, try JSONEncoder().encode(chat)])
            try db.execute(sql: "INSERT INTO messages(id,subchatID,createdAt,payload) VALUES (?,?,?,?)",
                           arguments: [message.id.uuidString, chat.id.uuidString, message.createdAt.timeIntervalSince1970, try JSONEncoder().encode(message)])
        }
        return (meeting, chat)
    }

    private func migrationIDs(_ root: URL) throws -> [String] {
        let queue = try DatabaseQueue(path: root.appendingPathComponent("copilot.sqlite").path)
        defer { try? queue.close() }
        return try queue.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier") }
    }
    private func writeCorruptTranscript(_ root: URL, meetingID: UUID) throws {
        let queue = try DatabaseQueue(path: root.appendingPathComponent("copilot.sqlite").path)
        defer { try? queue.close() }
        try queue.write { db in
            try db.execute(sql: "INSERT INTO meeting_transcripts(meetingID,payload) VALUES (?,?)",
                           arguments: [meetingID.uuidString, Data("{invalid}".utf8)])
        }
    }
}
