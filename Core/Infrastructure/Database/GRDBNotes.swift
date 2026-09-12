import Foundation
import GRDB

extension GRDBMeetingRepository: NoteRepository, NoteSearchService {
    public func note(id: UUID, profile: ProfileID) async throws -> Note {
        try await connection().read { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM notes WHERE id=? AND profileID=?", arguments: [id.uuidString, profile.rawValue]) else { throw LocalStoreError.missingRecord }
            return try JSONDecoder().decode(Note.self, from: data)
        }
    }
    public func notes(profile: ProfileID, query: String, includeArchived: Bool) async throws -> [Note] {
        try await connection().read { db in
            let data: [Data]
            if let query = NoteChunker.ftsQuery(query) {
                data = try Data.fetchAll(db, sql: """
                    SELECT DISTINCT n.payload FROM notes n JOIN note_chunks c ON c.noteID=n.id
                    JOIN note_fts ON note_fts.chunkID=c.id
                    WHERE note_fts MATCH ? AND n.profileID=? AND (? OR n.isArchived=0)
                    ORDER BY n.isPinned DESC, n.updatedAt DESC LIMIT 500
                    """, arguments: [query, profile.rawValue, includeArchived])
            } else {
                data = try Data.fetchAll(db, sql: "SELECT payload FROM notes WHERE profileID=? AND (? OR isArchived=0) ORDER BY isPinned DESC,updatedAt DESC LIMIT 500",
                                         arguments: [profile.rawValue, includeArchived])
            }
            return try data.map { try JSONDecoder().decode(Note.self, from: $0) }
        }
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
                INSERT INTO notes(id,profileID,isPinned,isArchived,allowAI,updatedAt,payload) VALUES (?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET isPinned=excluded.isPinned,isArchived=excluded.isArchived,
                allowAI=excluded.allowAI,updatedAt=excluded.updatedAt,payload=excluded.payload
                """, arguments: [updated.id.uuidString, updated.profileID.rawValue, updated.isPinned, updated.isArchived, updated.allowAI, updated.updatedAt.timeIntervalSince1970, payload])
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
