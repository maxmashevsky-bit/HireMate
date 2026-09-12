import Foundation

public protocol MeetingRepository: Sendable {
    func profiles() async throws -> [ContextProfile]
    func saveProfile(_ profile: ContextProfile) async throws
    func meetings(profile: ProfileID) async throws -> [Meeting]
    func createMeeting(_ meeting: Meeting, initialChat: Subchat) async throws
    func subchats(meetingID: UUID) async throws -> [Subchat]
    func saveSubchat(_ chat: Subchat) async throws
    func deleteSubchat(id: UUID, meetingID: UUID) async throws
    func messages(subchatID: UUID, meetingID: UUID) async throws -> [ChatMessage]
    func saveMessage(_ message: ChatMessage, meetingID: UUID) async throws
    func deleteMeeting(id: UUID) async throws
    func exportMeeting(id: UUID) async throws -> Data
}

public enum LocalStoreError: Error, LocalizedError, Sendable {
    case invalidData, missingRecord, unavailable
    public var errorDescription: String? {
        switch self {
        case .invalidData: "Локальная запись повреждена или имеет неподдерживаемый формат."
        case .missingRecord: "Локальная запись не найдена."
        case .unavailable: "Локальное хранилище недоступно. Новые данные не были сохранены."
        }
    }
}
