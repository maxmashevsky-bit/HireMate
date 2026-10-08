import Foundation

public protocol MeetingRepository: Sendable {
    func profiles() async throws -> [ContextProfile]
    func saveProfile(_ profile: ContextProfile) async throws
    func meetings(profile: ProfileID) async throws -> [Meeting]
    func meetingOverviews(profile: ProfileID) async throws -> [MeetingOverview]
    func renameMeeting(id: UUID, profile: ProfileID, title: String) async throws -> Meeting
    func createMeeting(_ meeting: Meeting, initialChat: Subchat) async throws
    func subchats(meetingID: UUID) async throws -> [Subchat]
    func saveSubchat(_ chat: Subchat) async throws
    func deleteSubchat(id: UUID, meetingID: UUID) async throws
    func messages(subchatID: UUID, meetingID: UUID) async throws -> [ChatMessage]
    func saveMessage(_ message: ChatMessage, meetingID: UUID) async throws
    func deleteMeeting(id: UUID) async throws
    func exportMeeting(id: UUID) async throws -> Data
}

public extension MeetingRepository {
    func meetingOverviews(profile: ProfileID) async throws -> [MeetingOverview] {
        var result: [MeetingOverview] = []
        for meeting in try await meetings(profile: profile) {
            let chats = try await subchats(meetingID: meeting.id)
            var count = 0
            for chat in chats { count += try await messages(subchatID: chat.id, meetingID: meeting.id).count }
            result.append(MeetingOverview(meeting: meeting, subchatCount: chats.count, messageCount: count))
        }
        return result
    }
    func renameMeeting(id: UUID, profile: ProfileID, title: String) async throws -> Meeting {
        throw LocalStoreError.unavailable
    }
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
