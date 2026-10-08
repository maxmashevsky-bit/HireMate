import Foundation
import GRDB

public actor GRDBMeetingRepository: MeetingRepository, TrackerRepository, TranscriptRepository {
    private var database: DatabaseQueue?
    private let directory: URL?
    public init(directory: URL? = nil) { self.directory = directory }

    func connection() throws -> DatabaseQueue {
        if let database { return database }
        let base = directory ?? AppStoragePaths.standard.directory(for: .database)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in try db.execute(sql: "PRAGMA secure_delete = ON") }
        let path = base.appendingPathComponent("copilot.sqlite").path
        let queue = try DatabaseQueue(path: path, configuration: configuration)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_profiles_and_meetings") { db in
            try db.create(table: "context_profiles") { t in
                t.column("id", .text).primaryKey(); t.column("payload", .blob).notNull()
            }
            try db.create(table: "meetings") { t in
                t.column("id", .text).primaryKey(); t.column("profileID", .text).notNull().indexed()
                t.column("createdAt", .double).notNull(); t.column("payload", .blob).notNull()
            }
            try db.create(table: "subchats") { t in
                t.column("id", .text).primaryKey()
                t.column("meetingID", .text).notNull().indexed().references("meetings", onDelete: .cascade)
                t.column("createdAt", .double).notNull(); t.column("payload", .blob).notNull()
            }
            try db.create(table: "messages") { t in
                t.column("id", .text).primaryKey()
                t.column("subchatID", .text).notNull().indexed().references("subchats", onDelete: .cascade)
                t.column("createdAt", .double).notNull(); t.column("payload", .blob).notNull()
            }
            for id in ProfileID.allCases {
                let payload = try JSONEncoder().encode(ContextProfile(id: id))
                try db.execute(sql: "INSERT INTO context_profiles(id, payload) VALUES (?, ?)", arguments: [id.rawValue, payload])
            }
        }
        migrator.registerMigration("v2_notes_fts") { db in
            try db.create(table: "notes") { t in
                t.column("id", .text).primaryKey(); t.column("profileID", .text).notNull().indexed()
                t.column("isPinned", .boolean).notNull(); t.column("isArchived", .boolean).notNull()
                t.column("allowAI", .boolean).notNull(); t.column("updatedAt", .double).notNull()
                t.column("payload", .blob).notNull()
            }
            try db.create(table: "note_chunks") { t in
                t.column("id", .text).primaryKey()
                t.column("noteID", .text).notNull().indexed().references("notes", onDelete: .cascade)
                t.column("payload", .blob).notNull()
            }
            try db.execute(sql: "CREATE VIRTUAL TABLE note_fts USING fts5(chunkID UNINDEXED, noteID UNINDEXED, title, body, tokenize='unicode61')")
        }
        migrator.registerMigration("v3_vacancy_tracker") { db in
            try db.create(table: "vacancy_stages") { t in
                t.column("id", .text).primaryKey()
                t.column("position", .integer).notNull().indexed()
                t.column("payload", .blob).notNull()
            }
            try db.create(table: "vacancies") { t in
                t.column("id", .text).primaryKey()
                t.column("stageID", .text).notNull().indexed().references("vacancy_stages")
                t.column("isArchived", .boolean).notNull().indexed()
                t.column("updatedAt", .double).notNull()
                t.column("payload", .blob).notNull()
            }
            try db.create(table: "vacancy_transitions") { t in
                t.column("id", .text).primaryKey()
                t.column("vacancyID", .text).notNull().indexed().references("vacancies", onDelete: .cascade)
                t.column("happenedAt", .double).notNull()
                t.column("payload", .blob).notNull()
            }
            for stage in VacancyStage.standard {
                try db.execute(sql: "INSERT INTO vacancy_stages(id,position,payload) VALUES (?,?,?)",
                               arguments: [stage.id.uuidString, stage.position, try JSONEncoder().encode(stage)])
            }
        }
        migrator.registerMigration("v4_meeting_transcripts") { db in
            try db.create(table: "meeting_transcripts") { t in
                t.column("meetingID", .text).primaryKey().references("meetings", onDelete: .cascade)
                t.column("payload", .blob).notNull()
            }
        }
        migrator.registerMigration("v5_note_library_paging") { db in
            try db.alter(table: "notes") { t in t.add(column: "folder", .text) }
            // Обновляется только индексируемая метаинформация; исходные payload и FTS не переписываются.
            let cursor = try Row.fetchCursor(db, sql: "SELECT id,payload FROM notes")
            while let row = try cursor.next() {
                let id: String = row["id"]
                let data: Data = row["payload"]
                let note = try JSONDecoder().decode(Note.self, from: data)
                try db.execute(sql: "UPDATE notes SET folder=? WHERE id=?", arguments: [note.folder, id])
            }
            try db.execute(sql: "CREATE INDEX note_library_order ON notes(profileID,isArchived,folder,isPinned DESC,updatedAt DESC,id)")
        }
        try migrator.migrate(queue)
        database = queue
        return queue
    }
    public func profiles() async throws -> [ContextProfile] {
        try await connection().read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM context_profiles ORDER BY id").map { try JSONDecoder().decode(ContextProfile.self, from: $0) }
        }
    }
    public func saveProfile(_ profile: ContextProfile) async throws {
        let payload = try JSONEncoder().encode(profile)
        try await connection().write { db in
            try db.execute(sql: "INSERT INTO context_profiles(id,payload) VALUES (?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload",
                           arguments: [profile.id.rawValue, payload])
        }
    }
    public func meetings(profile: ProfileID) async throws -> [Meeting] {
        try await connection().read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM meetings WHERE profileID=? ORDER BY createdAt DESC", arguments: [profile.rawValue])
                .map { try JSONDecoder().decode(Meeting.self, from: $0) }
        }
    }
    public func createMeeting(_ meeting: Meeting, initialChat: Subchat) async throws {
        guard !meeting.isEphemeral, initialChat.meetingID == meeting.id else { throw LocalStoreError.invalidData }
        let meetingPayload = try JSONEncoder().encode(meeting); let chatPayload = try JSONEncoder().encode(initialChat)
        try await connection().write { db in
            try db.execute(sql: "INSERT INTO meetings(id,profileID,createdAt,payload) VALUES (?,?,?,?)",
                           arguments: [meeting.id.uuidString, meeting.profileID.rawValue, meeting.createdAt.timeIntervalSince1970, meetingPayload])
            try db.execute(sql: "INSERT INTO subchats(id,meetingID,createdAt,payload) VALUES (?,?,?,?)",
                           arguments: [initialChat.id.uuidString, meeting.id.uuidString, initialChat.createdAt.timeIntervalSince1970, chatPayload])
        }
    }
    public func meetingOverviews(profile: ProfileID) async throws -> [MeetingOverview] {
        try await connection().read { db in
            try Row.fetchAll(db, sql: """
                SELECT m.payload, COUNT(DISTINCT s.id) AS chatCount, COUNT(msg.id) AS messageCount
                FROM meetings m LEFT JOIN subchats s ON s.meetingID=m.id
                LEFT JOIN messages msg ON msg.subchatID=s.id
                WHERE m.profileID=? GROUP BY m.id ORDER BY m.createdAt DESC
                """, arguments: [profile.rawValue]).map { row in
                    let payload: Data = row["payload"]
                    return MeetingOverview(meeting: try JSONDecoder().decode(Meeting.self, from: payload),
                                           subchatCount: row["chatCount"], messageCount: row["messageCount"])
                }
        }
    }
    public func renameMeeting(id: UUID, profile: ProfileID, title: String) async throws -> Meeting {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120 else { throw LocalStoreError.invalidData }
        return try await connection().write { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM meetings WHERE id=? AND profileID=?",
                                               arguments: [id.uuidString, profile.rawValue]) else { throw LocalStoreError.missingRecord }
            var meeting = try JSONDecoder().decode(Meeting.self, from: data)
            meeting.title = title; meeting.updatedAt = max(meeting.updatedAt, Date())
            try db.execute(sql: "UPDATE meetings SET payload=? WHERE id=? AND profileID=?",
                           arguments: [try JSONEncoder().encode(meeting), id.uuidString, profile.rawValue])
            return meeting
        }
    }
    public func subchats(meetingID: UUID) async throws -> [Subchat] {
        try await connection().read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM subchats WHERE meetingID=? ORDER BY createdAt", arguments: [meetingID.uuidString])
                .map { try JSONDecoder().decode(Subchat.self, from: $0) }
        }
    }
    public func saveSubchat(_ chat: Subchat) async throws {
        let payload = try JSONEncoder().encode(chat)
        try await connection().write { db in
            try db.execute(sql: "INSERT INTO subchats(id,meetingID,createdAt,payload) VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload WHERE subchats.meetingID=excluded.meetingID",
                           arguments: [chat.id.uuidString, chat.meetingID.uuidString, chat.createdAt.timeIntervalSince1970, payload])
        }
    }
    public func deleteSubchat(id: UUID, meetingID: UUID) async throws {
        try await connection().write { db in
            try db.execute(sql: "DELETE FROM subchats WHERE id=? AND meetingID=?", arguments: [id.uuidString, meetingID.uuidString])
        }
    }
    public func messages(subchatID: UUID, meetingID: UUID) async throws -> [ChatMessage] {
        try await connection().read { db in
            try Data.fetchAll(db, sql: "SELECT m.payload FROM messages m JOIN subchats s ON s.id=m.subchatID WHERE m.subchatID=? AND s.meetingID=? ORDER BY m.createdAt,m.rowid",
                              arguments: [subchatID.uuidString, meetingID.uuidString]).map { try JSONDecoder().decode(ChatMessage.self, from: $0) }
        }
    }
    public func saveMessage(_ message: ChatMessage, meetingID: UUID) async throws {
        let payload = try JSONEncoder().encode(message)
        try await connection().write { db in
            let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM subchats WHERE id=? AND meetingID=?)", arguments: [message.subchatID.uuidString, meetingID.uuidString]) ?? false
            guard exists else { throw LocalStoreError.missingRecord }
            try db.execute(sql: "INSERT INTO messages(id,subchatID,createdAt,payload) VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload WHERE messages.subchatID=excluded.subchatID",
                           arguments: [message.id.uuidString, message.subchatID.uuidString, message.createdAt.timeIntervalSince1970, payload])
            if let data = try Data.fetchOne(db, sql: "SELECT payload FROM meetings WHERE id=?", arguments: [meetingID.uuidString]) {
                var parent = try JSONDecoder().decode(Meeting.self, from: data)
                parent.updatedAt = max(parent.updatedAt, message.createdAt)
                try db.execute(sql: "UPDATE meetings SET payload=? WHERE id=?",
                               arguments: [try JSONEncoder().encode(parent), meetingID.uuidString])
            }
        }
    }
    public func deleteMeeting(id: UUID) async throws {
        try await connection().write { db in try db.execute(sql: "DELETE FROM meetings WHERE id=?", arguments: [id.uuidString]) }
    }
    public func transcriptTimeline(meetingID: UUID, profile: ProfileID) async throws -> TranscriptTimeline {
        try await connection().read { db in
            let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM meetings WHERE id=? AND profileID=?)",
                                           arguments: [meetingID.uuidString, profile.rawValue]) ?? false
            guard exists else { throw LocalStoreError.missingRecord }
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM meeting_transcripts WHERE meetingID=?",
                                               arguments: [meetingID.uuidString]) else { return TranscriptTimeline() }
            guard data.count <= 300_000, let timeline = try? JSONDecoder().decode(TranscriptTimeline.self, from: data) else {
                throw LocalStoreError.invalidData
            }
            return timeline
        }
    }
    public func saveTranscriptTimeline(_ timeline: TranscriptTimeline, meetingID: UUID, profile: ProfileID) async throws {
        let data = try JSONEncoder().encode(timeline)
        guard data.count <= 300_000, (try? JSONDecoder().decode(TranscriptTimeline.self, from: data)) != nil else {
            throw LocalStoreError.invalidData
        }
        try await connection().write { db in
            let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM meetings WHERE id=? AND profileID=?)",
                                           arguments: [meetingID.uuidString, profile.rawValue]) ?? false
            guard exists else { throw LocalStoreError.missingRecord }
            try db.execute(sql: "INSERT INTO meeting_transcripts(meetingID,payload) VALUES (?,?) ON CONFLICT(meetingID) DO UPDATE SET payload=excluded.payload",
                           arguments: [meetingID.uuidString, data])
        }
    }
    public func exportMeeting(id: UUID) async throws -> Data {
        struct Archive: Encodable { let version: Int; let meeting: Meeting; let subchats: [Subchat]; let messages: [ChatMessage] }
        return try await connection().read { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM meetings WHERE id=?", arguments: [id.uuidString]) else { throw LocalStoreError.missingRecord }
            let meeting = try JSONDecoder().decode(Meeting.self, from: data)
            let chats = try Data.fetchAll(db, sql: "SELECT payload FROM subchats WHERE meetingID=? ORDER BY createdAt", arguments: [id.uuidString]).map { try JSONDecoder().decode(Subchat.self, from: $0) }
            let messages = try Data.fetchAll(db, sql: "SELECT m.payload FROM messages m JOIN subchats s ON s.id=m.subchatID WHERE s.meetingID=? ORDER BY m.createdAt,m.rowid", arguments: [id.uuidString]).map { try JSONDecoder().decode(ChatMessage.self, from: $0) }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(Archive(version: 1, meeting: meeting, subchats: chats, messages: messages))
        }
    }

    public func vacancyStages() async throws -> [VacancyStage] {
        try await connection().read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM vacancy_stages ORDER BY position,id")
                .map { try JSONDecoder().decode(VacancyStage.self, from: $0) }
        }
    }

    public func saveVacancyStages(_ stages: [VacancyStage]) async throws {
        guard !stages.isEmpty, Set(stages.map(\.id)).count == stages.count,
              stages.allSatisfy(\.isValid) else { throw LocalStoreError.invalidData }
        try await connection().write { db in
            for (position, value) in stages.enumerated() {
                var stage = value; stage.position = position
                let payload = try JSONEncoder().encode(stage)
                try db.execute(sql: "INSERT INTO vacancy_stages(id,position,payload) VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET position=excluded.position,payload=excluded.payload",
                               arguments: [stage.id.uuidString, position, payload])
            }
        }
    }

    public func vacancies(includeArchived: Bool) async throws -> [Vacancy] {
        try await connection().read { db in
            let sql = includeArchived
                ? "SELECT payload FROM vacancies ORDER BY updatedAt DESC,id"
                : "SELECT payload FROM vacancies WHERE isArchived=0 ORDER BY updatedAt DESC,id"
            return try Data.fetchAll(db, sql: sql).map { try JSONDecoder().decode(Vacancy.self, from: $0) }
        }
    }

    public func saveVacancy(_ vacancy: Vacancy) async throws {
        guard vacancy.isValid else { throw LocalStoreError.invalidData }
        let payload = try JSONEncoder().encode(vacancy)
        try await connection().write { db in
            let stageExists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM vacancy_stages WHERE id=?)",
                                                arguments: [vacancy.stageID.uuidString]) ?? false
            guard stageExists else { throw LocalStoreError.missingRecord }
            try db.execute(sql: "INSERT INTO vacancies(id,stageID,isArchived,updatedAt,payload) VALUES (?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET stageID=excluded.stageID,isArchived=excluded.isArchived,updatedAt=excluded.updatedAt,payload=excluded.payload",
                           arguments: [vacancy.id.uuidString, vacancy.stageID.uuidString, vacancy.isArchived,
                                       vacancy.updatedAt.timeIntervalSince1970, payload])
        }
    }

    public func moveVacancy(id: UUID, to stageID: UUID, at date: Date = .now) async throws {
        try await connection().write { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM vacancies WHERE id=? AND isArchived=0",
                                               arguments: [id.uuidString]) else { throw LocalStoreError.missingRecord }
            let stageExists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM vacancy_stages WHERE id=?)",
                                                arguments: [stageID.uuidString]) ?? false
            guard stageExists else { throw LocalStoreError.missingRecord }
            var vacancy = try JSONDecoder().decode(Vacancy.self, from: data)
            guard vacancy.stageID != stageID else { return }
            let transition = VacancyTransition(vacancyID: id, fromStageID: vacancy.stageID,
                                                toStageID: stageID, happenedAt: date)
            vacancy.stageID = stageID; vacancy.updatedAt = date
            try db.execute(sql: "UPDATE vacancies SET stageID=?,updatedAt=?,payload=? WHERE id=?",
                           arguments: [stageID.uuidString, date.timeIntervalSince1970,
                                       try JSONEncoder().encode(vacancy), id.uuidString])
            try db.execute(sql: "INSERT INTO vacancy_transitions(id,vacancyID,happenedAt,payload) VALUES (?,?,?,?)",
                           arguments: [transition.id.uuidString, id.uuidString, date.timeIntervalSince1970,
                                       try JSONEncoder().encode(transition)])
        }
    }

    public func setVacancyArchived(id: UUID, archived: Bool, at date: Date = .now) async throws {
        try await connection().write { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM vacancies WHERE id=?",
                                               arguments: [id.uuidString]) else { throw LocalStoreError.missingRecord }
            var vacancy = try JSONDecoder().decode(Vacancy.self, from: data)
            vacancy.isArchived = archived; vacancy.updatedAt = date
            try db.execute(sql: "UPDATE vacancies SET isArchived=?,updatedAt=?,payload=? WHERE id=?",
                           arguments: [archived, date.timeIntervalSince1970,
                                       try JSONEncoder().encode(vacancy), id.uuidString])
        }
    }

    public func vacancyTransitions() async throws -> [VacancyTransition] {
        try await connection().read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM vacancy_transitions ORDER BY happenedAt,id")
                .map { try JSONDecoder().decode(VacancyTransition.self, from: $0) }
        }
    }
}
