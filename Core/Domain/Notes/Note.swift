import Foundation
import CryptoKit

public struct Note: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let profileID: ProfileID
    public var title: String
    public var markdown: String
    public var folder: String?
    public var tags: [String] = []
    public var isPinned = false
    public var isArchived = false
    public var allowAI = false
    public var sourcePath: String?
    public var sourceHash: String?
    public var contentHash: String
    public let createdAt: Date
    public var updatedAt: Date
    public init(profileID: ProfileID, title: String = "Новая заметка", markdown: String = "") {
        id = UUID(); self.profileID = profileID; self.title = title; self.markdown = markdown
        createdAt = Date(); updatedAt = createdAt; contentHash = Self.hash(markdown)
    }
    public static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    public var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 200 && markdown.utf8.count <= 1_048_576
            && tags.count <= 30 && tags.allSatisfy { !$0.isEmpty && $0.count <= 80 }
    }
}

public struct NoteFragment: Codable, Identifiable, Sendable, Equatable {
    public var id: String { "\(noteID.uuidString):\(index):\(sourceHash)" }
    public let noteID: UUID
    public let profileID: ProfileID
    public let title: String
    public let tags: [String]
    public let index: Int
    public let text: String
    public let sourceHash: String
    public var score: Double?
    public init(note: Note, index: Int, text: String) {
        noteID = note.id; profileID = note.profileID; title = note.title; tags = note.tags
        self.index = index; self.text = text; sourceHash = note.contentHash
    }
}

public enum NoteChunker {
    /// Разбивка по абзацам/заголовкам, длинные блоки — по Unicode Characters с overlap 100.
    public static func chunks(_ note: Note, limit: Int = 800, overlap: Int = 100) -> [NoteFragment] {
        let maximum = min(2_000, max(200, limit)); let carry = min(maximum / 3, max(0, overlap))
        let text = note.markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var blocks: [String] = []; var paragraph = ""
        for line in text.components(separatedBy: "\n") {
            if line.isEmpty || line.hasPrefix("#") {
                if !paragraph.isEmpty { blocks.append(paragraph); paragraph = "" }
                if !line.isEmpty { paragraph = line }
            } else { paragraph += (paragraph.isEmpty ? "" : "\n") + line }
        }
        if !paragraph.isEmpty { blocks.append(paragraph) }
        if blocks.isEmpty { blocks = [note.title] }
        var output: [String] = []
        for block in blocks {
            let characters = Array(block)
            var start = 0
            while start < characters.count {
                let end = min(characters.count, start + maximum)
                output.append(String(characters[start..<end]))
                if end == characters.count { break }
                start = end - carry
            }
        }
        return output.enumerated().map { NoteFragment(note: note, index: $0.offset, text: $0.element) }
    }
    public static func ftsQuery(_ text: String) -> String? {
        let tokens = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 2 }.prefix(12)
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"" }.joined(separator: " OR ")
    }
}

public protocol NoteRepository: Sendable {
    func note(id: UUID, profile: ProfileID) async throws -> Note
    func notes(profile: ProfileID, query: String, includeArchived: Bool) async throws -> [Note]
    func saveNote(_ note: Note) async throws
    func deleteNote(id: UUID, profile: ProfileID) async throws
}
public protocol NoteSearchService: Sendable {
    func retrieve(query: String, profile: ProfileID, tags: [String], limit: Int) async throws -> [NoteFragment]
}
