import Foundation

public struct NoteFolderCount: Equatable, Sendable, Identifiable {
    /// Пустая строка обозначает «Без папки»; nil в запросе обозначает все папки.
    public let name: String
    public let count: Int
    public var id: String { name }
    public init(name: String, count: Int) { self.name = name; self.count = count }
}

public struct NoteLibraryPage: Equatable, Sendable {
    public let notes: [Note]
    public let totalCount: Int
    public let folders: [NoteFolderCount]
    public let offset: Int
    public let limit: Int
    public var hasNext: Bool { offset + notes.count < totalCount }
    public init(notes: [Note], totalCount: Int, folders: [NoteFolderCount], offset: Int, limit: Int) {
        self.notes = notes; self.totalCount = totalCount; self.folders = folders; self.offset = offset; self.limit = limit
    }
}

public protocol NoteLibraryPaging: Sendable {
    func noteLibraryPage(profile: ProfileID, query: String, includeArchived: Bool, folder: String?,
                         offset: Int, limit: Int) async throws -> NoteLibraryPage
}
