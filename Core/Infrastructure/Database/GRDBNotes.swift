import Foundation
import GRDB

extension GRDBMeetingRepository: NoteRepository, NoteSearchService, NoteIndexInspecting, NoteLibraryPaging {
    public func noteLibraryPage(profile: ProfileID, query: String, includeArchived: Bool, folder: String?,
                                offset: Int, limit: Int) async throws -> NoteLibraryPage {
        guard (0...1_048_576).contains(offset), (1...100).contains(limit), query.utf8.count <= 4_096 else { throw LocalStoreError.invalidData }
        try Task.checkCancellation()
        let queryText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let match = NoteChunker.ftsQuery(queryText)
        if !queryText.isEmpty, match == nil {
            return NoteLibraryPage(notes: [], totalCount: 0, folders: [], offset: offset, limit: limit)
        }
        return try await connection().read { db in
            var condition = "n.profileID=? AND (? OR n.isArchived=0)"
            var arguments: StatementArguments = [profile.rawValue, includeArchived]
            if let match {
                condition += " AND n.id IN (SELECT noteID FROM note_fts WHERE note_fts MATCH ?)"
                arguments += StatementArguments([match])
            }
            let folders = try Row.fetchAll(db, sql: "SELECT COALESCE(n.folder,'') AS name,COUNT(*) AS count FROM notes n WHERE \(condition) GROUP BY COALESCE(n.folder,'') ORDER BY name",
                                          arguments: arguments).map { row in NoteFolderCount(name: row["name"], count: row["count"]) }
            if let folder {
                condition += " AND COALESCE(n.folder,'')=?"
                arguments += StatementArguments([folder])
            }
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes n WHERE \(condition)", arguments: arguments) ?? 0
            let rows = try Row.fetchAll(db, sql: "SELECT n.id,n.payload FROM notes n WHERE \(condition) ORDER BY n.isPinned DESC,n.updatedAt DESC,n.id LIMIT ? OFFSET ?",
                                       arguments: arguments + StatementArguments([limit, offset]))
            let notes = try rows.map { row -> Note in
                let data: Data = row["payload"]
                let id: String = row["id"]
                return try Self.decodeNote(data, id: id, profile: profile)
            }
            return NoteLibraryPage(notes: notes, totalCount: count, folders: folders, offset: offset, limit: limit)
        }
    }
    public func noteIndexPage(id: UUID, profile: ProfileID, offset: Int, limit: Int) async throws -> NoteIndexPage {
        guard (0...1_048_576).contains(offset), (1...100).contains(limit) else { throw LocalStoreError.invalidData }
        try Task.checkCancellation()
        return try await connection().read { db in
            guard let payload = try Data.fetchOne(db, sql: "SELECT payload FROM notes WHERE id=? AND profileID=?", arguments: [id.uuidString, profile.rawValue]) else { throw LocalStoreError.missingRecord }
            guard payload.count <= 8_388_608, let note = try? JSONDecoder().decode(Note.self, from: payload),
                  note.id == id, note.profileID == profile, note.isValid, Note.hash(note.markdown) == note.contentHash else { throw LocalStoreError.invalidData }
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_chunks WHERE noteID=?", arguments: [id.uuidString]) ?? 0
            let rows = try Data.fetchAll(db, sql: "SELECT payload FROM note_chunks WHERE noteID=? ORDER BY rowid LIMIT ? OFFSET ?",
                                         arguments: [id.uuidString, limit, offset])
            let fragments = try rows.map { data -> NoteFragment in
                guard data.count <= 65_536, let fragment = try? JSONDecoder().decode(NoteFragment.self, from: data),
                      fragment.noteID == id, fragment.profileID == profile, fragment.sourceHash == note.contentHash,
                      fragment.title == note.title, fragment.tags == note.tags,
                      fragment.index >= 0, fragment.index < count, !fragment.text.isEmpty, fragment.text.count <= 2_000 else { throw LocalStoreError.invalidData }
                return fragment
            }
            guard Set(fragments.map(\.id)).count == fragments.count else { throw LocalStoreError.invalidData }
            return NoteIndexPage(note: note, fragments: fragments, totalCount: count, offset: offset, limit: limit)
        }
    }
    public func note(id: UUID, profile: ProfileID) async throws -> Note {
        try await connection().read { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM notes WHERE id=? AND profileID=?", arguments: [id.uuidString, profile.rawValue]) else { throw LocalStoreError.missingRecord }
            return try Self.decodeNote(data, id: id.uuidString, profile: profile)
        }
    }
    public func notes(profile: ProfileID, query: String, includeArchived: Bool) async throws -> [Note] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty, NoteChunker.ftsQuery(query) == nil { return [] }
        return try await connection().read { db in
            let rows: [Row]
            if let query = NoteChunker.ftsQuery(query) {
                rows = try Row.fetchAll(db, sql: """
                    SELECT DISTINCT n.id,n.payload FROM notes n JOIN note_chunks c ON c.noteID=n.id
                    JOIN note_fts ON note_fts.chunkID=c.id
                    WHERE note_fts MATCH ? AND n.profileID=? AND (? OR n.isArchived=0)
                    ORDER BY n.isPinned DESC, n.updatedAt DESC, n.id LIMIT 500
                    """, arguments: [query, profile.rawValue, includeArchived])
            } else {
                rows = try Row.fetchAll(db, sql: "SELECT id,payload FROM notes WHERE profileID=? AND (? OR isArchived=0) ORDER BY isPinned DESC,updatedAt DESC,id LIMIT 500",
                                         arguments: [profile.rawValue, includeArchived])
            }
            return try rows.map { row in
                let data: Data = row["payload"]; let id: String = row["id"]
                return try Self.decodeNote(data, id: id, profile: profile)
            }
        }
    }
    private nonisolated static func decodeNote(_ data: Data, id: String, profile: ProfileID) throws -> Note {
        guard data.count <= 8_388_608, let note = try? JSONDecoder().decode(Note.self, from: data),
              note.id.uuidString == id, note.profileID == profile, note.isValid,
              note.contentHash == Note.hash(note.markdown) else { throw LocalStoreError.invalidData }
        return note
    }
    public func saveNote(_ note: Note) async throws {
        guard note.isValid else { throw LocalStoreError.invalidData }
        var updated = note; updated.updatedAt = Date(); updated.contentHash = Note.hash(updated.markdown)
        let payload = try JSONEncoder().encode(updated)
        let fragments = NoteChunker.chunks(updated)
        try Task.checkCancellation()
        try await connection().write { [updated] db in
            let owner = try String.fetchOne(db, sql: "SELECT profileID FROM notes WHERE id=?", arguments: [updated.id.uuidString])
            guard owner == nil || owner == updated.profileID.rawValue else { throw LocalStoreError.invalidData }
            try db.execute(sql: """
                INSERT INTO notes(id,profileID,isPinned,isArchived,allowAI,updatedAt,payload,folder) VALUES (?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET isPinned=excluded.isPinned,isArchived=excluded.isArchived,
                allowAI=excluded.allowAI,updatedAt=excluded.updatedAt,payload=excluded.payload,folder=excluded.folder
                """, arguments: [updated.id.uuidString, updated.profileID.rawValue, updated.isPinned, updated.isArchived, updated.allowAI, updated.updatedAt.timeIntervalSince1970, payload, updated.folder])
            try db.execute(sql: "DELETE FROM note_fts WHERE noteID=?", arguments: [updated.id.uuidString])
            try db.execute(sql: "DELETE FROM note_chunks WHERE noteID=?", arguments: [updated.id.uuidString])
            for fragment in fragments {
                try Task.checkCancellation()
                try db.execute(sql: "INSERT INTO note_chunks(id,noteID,payload) VALUES (?,?,?)", arguments: [fragment.id, updated.id.uuidString, try JSONEncoder().encode(fragment)])
                try db.execute(sql: "INSERT INTO note_fts(chunkID,noteID,title,body) VALUES (?,?,?,?)", arguments: [fragment.id, updated.id.uuidString, updated.title, fragment.text])
            }
        }
    }
    public func deleteNote(id: UUID, profile: ProfileID) async throws {
        try await connection().write { db in
            guard try String.fetchOne(db, sql: "SELECT profileID FROM notes WHERE id=?", arguments: [id.uuidString]) == profile.rawValue else { throw LocalStoreError.missingRecord }
            try db.execute(sql: "DELETE FROM note_fts WHERE noteID=?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM notes WHERE id=? AND profileID=?", arguments: [id.uuidString, profile.rawValue])
        }
    }
    public func retrieve(query: String, profile: ProfileID, tags: [String], limit: Int) async throws -> [NoteFragment] {
        guard let query = NoteChunker.ftsQuery(query) else { return [] }
        return try await connection().read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.payload AS chunk, n.payload AS note, bm25(note_fts) AS score
                FROM note_fts JOIN note_chunks c ON c.id=note_fts.chunkID JOIN notes n ON n.id=c.noteID
                WHERE note_fts MATCH ? AND n.profileID=? AND n.allowAI=1 AND n.isArchived=0
                ORDER BY score LIMIT 80
                """, arguments: [query, profile.rawValue])
            var result: [NoteFragment] = []
            for row in rows {
                let chunkData: Data = row["chunk"]; let noteData: Data = row["note"]
                var fragment = try JSONDecoder().decode(NoteFragment.self, from: chunkData)
                let note = try JSONDecoder().decode(Note.self, from: noteData)
                guard fragment.sourceHash == note.contentHash, fragment.profileID == profile,
                      tags.isEmpty || !Set(tags).isDisjoint(with: note.tags) else { continue }
                fragment.score = row["score"]; result.append(fragment)
                if result.count >= min(4, max(1, limit)) { break }
            }
            return result
        }
    }
}
