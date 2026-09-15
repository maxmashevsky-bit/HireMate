import Foundation

/// Переносимый документ заметки. Не переносит разрешение AI или абсолютный путь пользователя.
public struct NoteArchive: Codable, Sendable {
    public let format: String
    public let version: Int
    public let title: String
    public let markdown: String
    public let folder: String?
    public let tags: [String]
    public let profileID: ProfileID
    public let isPinned: Bool
    public let isArchived: Bool
    public let createdAt: Date
    public let updatedAt: Date
    public let contentHash: String
    public let originalSourceHash: String?
    public init(note: Note) {
        format = "max-interview-note"; version = 1
        title = note.title; markdown = note.markdown; folder = note.folder; tags = note.tags; profileID = note.profileID
        isPinned = note.isPinned; isArchived = note.isArchived
        createdAt = note.createdAt; updatedAt = note.updatedAt
        contentHash = Note.hash(note.markdown); originalSourceHash = note.sourceHash
    }
    public func encode() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data) throws -> NoteArchive {
        guard data.count <= 8_388_608 else { throw LocalStoreError.invalidData }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(Self.self, from: data)
        guard archive.format == "max-interview-note", archive.version == 1,
              archive.contentHash == Note.hash(archive.markdown),
              archive.markdown.utf8.count <= 1_048_576,
              !archive.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              archive.title.count <= 200, archive.tags.count <= 30,
              (archive.folder?.count ?? 0) <= 200,
              archive.tags.allSatisfy({ !$0.isEmpty && $0.count <= 80 }),
              archive.createdAt.timeIntervalSince1970.isFinite, archive.updatedAt.timeIntervalSince1970.isFinite else { throw LocalStoreError.invalidData }
        return archive
    }
    public func importedNote() -> Note {
        // Новый UUID предотвращает перезапись существующей заметки при повторном импорте.
        var note = Note(profileID: profileID, title: title, markdown: markdown)
        note.folder = folder; note.tags = tags; note.isPinned = isPinned; note.isArchived = isArchived
        note.sourceHash = originalSourceHash; note.allowAI = false
        return note
    }
}
