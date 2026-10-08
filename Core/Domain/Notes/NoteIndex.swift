import Foundation

public struct NoteIndexPage: Sendable {
    public let note: Note
    public let fragments: [NoteFragment]
    public let totalCount: Int
    public let offset: Int
    public let limit: Int
    public init(note: Note, fragments: [NoteFragment], totalCount: Int, offset: Int, limit: Int) {
        self.note = note; self.fragments = fragments; self.totalCount = totalCount
        self.offset = offset; self.limit = limit
    }
    public var hasNext: Bool { offset + fragments.count < totalCount }
}

public protocol NoteIndexInspecting: Sendable {
    func noteIndexPage(id: UUID, profile: ProfileID, offset: Int, limit: Int) async throws -> NoteIndexPage
}
