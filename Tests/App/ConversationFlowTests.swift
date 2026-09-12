import XCTest
import CopilotCore

@MainActor
private final class UnusedSecrets: SecureSecretStore {
    func save(_ secret: String) throws { XCTFail("Демо не должно сохранять ключи") }
    func read() throws -> String? { XCTFail("Демо не должно читать ключи"); return nil }
    func delete() throws { XCTFail("Демо не должно удалять ключи") }
}

final class ConversationFlowTests: XCTestCase {
    @MainActor
    func testSavedMeetingKeepsBoundedWindowButExportsCompleteHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = GRDBMeetingRepository(directory: directory)
        let meeting = Meeting(profileID: .technical, title: "Длинная встреча", isEphemeral: false)
        let chat = Subchat(meetingID: meeting.id, title: "Основной")
        try await repository.createMeeting(meeting, initialChat: chat)
        for index in 0..<205 {
            try await repository.saveMessage(
                ChatMessage(subchatID: chat.id, role: .user, content: "Сообщение \(index)"),
                meetingID: meeting.id
            )
        }

        let model = ConversationModel(profileID: .technical, repository: repository,
                                      secrets: UnusedSecrets(), network: NetworkClient())
        await model.open(meeting)
        XCTAssertEqual(model.messages.count, 200)
        XCTAssertEqual(model.hiddenMessageCount, 5)

        let data = try await model.exportCurrent()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(MeetingArchive.self, from: data)
        XCTAssertEqual(archive.messages.count, 205)
        XCTAssertEqual(archive.messages.first?.content, "Сообщение 0")
        XCTAssertEqual(archive.messages.last?.content, "Сообщение 204")
    }

    @MainActor
    func testEphemeralMeetingLimitsCachedSubchats() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ConversationModel(profileID: .technical, repository: GRDBMeetingRepository(directory: directory),
                                      secrets: UnusedSecrets(), network: NetworkClient())
        for index in 1..<8 {
            model.newChatTitle = "Поддиалог \(index)"
            await model.createSubchat()
        }
        XCTAssertEqual(model.chats.count, 8)
        model.newChatTitle = "Лишний"
        await model.createSubchat()
        XCTAssertEqual(model.chats.count, 8)
        XCTAssertTrue(model.status.contains("ограничен восемью"))
    }

    @MainActor
    func testMeasuresFirstTokenAndCompletionWithoutRequestPayload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ConversationModel(profileID: .technical, repository: GRDBMeetingRepository(directory: directory),
                                      secrets: UnusedSecrets(), network: NetworkClient(),
                                      providerFactory: { _ in TimedStreamingProvider() })
        model.draft = "Проверить локальные метрики"
        model.send(configuration: ModelConfiguration())
        try await waitUntil { !model.isGenerating }
        let first = try XCTUnwrap(model.lastFirstTokenMilliseconds)
        let total = try XCTUnwrap(model.lastLLMRequestMilliseconds)
        XCTAssertGreaterThanOrEqual(first, 15)
        XCTAssertGreaterThanOrEqual(total, first)
        XCTAssertEqual(model.lastLLMRequestSucceeded, true)
        model.clearLatencyMetrics()
        XCTAssertNil(model.lastLLMRequestMilliseconds)
    }

    @MainActor
    func testOversizedStreamStopsAndKeepsAcceptedPartialAnswer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ConversationModel(profileID: .technical, repository: GRDBMeetingRepository(directory: directory),
                                      secrets: UnusedSecrets(), network: NetworkClient(),
                                      providerFactory: { _ in OversizedStreamingProvider() })
        model.draft = "Проверить предел ответа"
        model.send(configuration: ModelConfiguration())
        try await waitUntil { !model.isGenerating }
        XCTAssertEqual(model.answer, "Принятая часть")
        XCTAssertEqual(model.messages.last?.state, .failed)
        XCTAssertEqual(model.lastLLMRequestSucceeded, false)
        XCTAssertTrue(model.status.contains("безопасный размер"))
    }
    @MainActor
    func testDeleteWaitsForPreviouslyCancelledQuestionWrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = GRDBMeetingRepository(directory: directory)
        let repository = DelayedChatRepository(base: base)
        await repository.delayQuestionWrite()
        let model = ConversationModel(profileID: .hr, repository: repository, secrets: UnusedSecrets(), network: NetworkClient())
        model.saveNewMeetingHistory = true
        await model.createMeeting()
        let meeting = model.meeting
        model.draft = "Вопрос перед удалением"
        model.send(configuration: ModelConfiguration())
        for _ in 0..<100 {
            if await repository.isQuestionWaiting { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let waiting = await repository.isQuestionWaiting
        XCTAssertTrue(waiting)
        model.cancel()
        let deletion = Task { await model.deleteMeeting(meeting) }
        try await waitUntil { model.isLoading }
        await repository.releaseQuestionWrite()
        await deletion.value
        await model.finishForTermination()
        XCTAssertTrue(model.meeting.isEphemeral)
        XCTAssertEqual(model.unsavedMessageCount, 0)
        let remaining = try await base.meetings(profile: .hr)
        XCTAssertTrue(remaining.isEmpty)
    }
    @MainActor
    func testFailedQuestionWriteIsRetriedBeforeTermination() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = GRDBMeetingRepository(directory: directory)
        let repository = DelayedChatRepository(base: base)
        await repository.rejectUserWrites()
        let model = ConversationModel(profileID: .hr, repository: repository, secrets: UnusedSecrets(), network: NetworkClient())
        model.saveNewMeetingHistory = true
        await model.createMeeting()
        model.draft = "Вопрос, который нельзя потерять"
        model.send(configuration: ModelConfiguration())
        try await waitUntil { !model.isGenerating }
        XCTAssertEqual(model.unsavedMessageCount, 1)
        await repository.allowMessageWrites()
        await model.finishForTermination()
        XCTAssertEqual(model.unsavedMessageCount, 0)
        let saved = try await base.messages(subchatID: model.activeChatID, meetingID: model.meeting.id)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.content, "Вопрос, который нельзя потерять")
    }
    @MainActor
    func testFailedAnswerCanBeSavedAgainWithoutDuplicates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = GRDBMeetingRepository(directory: directory)
        let repository = DelayedChatRepository(base: base, failAssistantWrites: true)
        let model = ConversationModel(profileID: .hr, repository: repository, secrets: UnusedSecrets(), network: NetworkClient())
        model.saveNewMeetingHistory = true
        await model.createMeeting()
        model.draft = "Мой опыт"
        model.send(configuration: ModelConfiguration())
        try await waitUntil { !model.isGenerating }
        await model.flushPendingMessages()
        XCTAssertEqual(model.unsavedMessageCount, 1)
        await repository.allowMessageWrites()
        await model.retryUnsavedMessages()
        await model.retryUnsavedMessages()
        XCTAssertEqual(model.unsavedMessageCount, 0)
        let saved = try await base.messages(subchatID: model.activeChatID, meetingID: model.meeting.id)
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.last?.content, model.answer)
    }
    @MainActor
    func testUnsavedAnswerSurvivesSwitchingChats() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = DelayedChatRepository(base: GRDBMeetingRepository(directory: directory), failAssistantWrites: true)
        await repository.release(fail: false)
        let model = ConversationModel(profileID: .hr, repository: repository, secrets: UnusedSecrets(), network: NetworkClient())
        model.saveNewMeetingHistory = true
        await model.createMeeting()
        let first = model.activeChatID
        model.draft = "Мой опыт"
        model.send(configuration: ModelConfiguration())
        try await waitUntil { !model.isGenerating }
        let answer = model.answer
        XCTAssertFalse(answer.isEmpty)
        await model.createSubchat()
        model.requestSwitch(first)
        try await waitUntil { model.activeChatID == first && !model.isLoading }
        XCTAssertEqual(model.answer, answer)
        XCTAssertEqual(model.messages.count, 2)
    }

    @MainActor
    func testDeleteChatBlocksRepeatedDeletionAndKeepsLastChat() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = DelayedChatRepository(base: GRDBMeetingRepository(directory: directory), delayDelete: true)
        let model = ConversationModel(profileID: .technical, repository: repository, secrets: UnusedSecrets(), network: NetworkClient())
        model.saveNewMeetingHistory = true
        await model.createMeeting()
        let first = model.activeChatID
        await model.createSubchat()
        let deletion = Task { await model.deleteActiveChat() }
        try await waitUntil { model.isLoading }
        await model.deleteActiveChat()
        model.draft = "Не отправлять в удаляемый диалог"
        model.send(configuration: ModelConfiguration())
        XCTAssertFalse(model.isGenerating)
        await repository.release(fail: false)
        await deletion.value
        XCTAssertEqual(model.chats.count, 1)
        XCTAssertEqual(model.activeChatID, first)
        await model.deleteActiveChat()
        XCTAssertEqual(model.chats.count, 1)
        let deletes = await repository.deleteCount
        XCTAssertEqual(deletes, 1)
    }

    @MainActor
    func testCreatingChatBlocksDuplicateAndSendWhileSaving() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = DelayedChatRepository(base: GRDBMeetingRepository(directory: directory))
        let model = ConversationModel(profileID: .technical, repository: repository,
                                      secrets: UnusedSecrets(), network: NetworkClient())
        model.saveNewMeetingHistory = true
        await model.createMeeting()
        model.draft = "Старый черновик"
        let creation = Task { await model.createSubchat() }
        try await waitUntil { model.isLoading }
        await model.createSubchat()
        model.send(configuration: ModelConfiguration())
        XCTAssertFalse(model.isGenerating)
        XCTAssertTrue(model.messages.isEmpty)
        model.draft = "Текст, введённый во время сохранения"
        await repository.release(fail: false)
        await creation.value
        XCTAssertEqual(model.chats.count, 2)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.draft, "Текст, введённый во время сохранения")
        let saves = await repository.saveCount
        XCTAssertEqual(saves, 1)
    }

    @MainActor
    func testLateChatSaveFailureDoesNotChangeNewProfile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = DelayedChatRepository(base: GRDBMeetingRepository(directory: directory))
        let model = ConversationModel(profileID: .technical, repository: repository,
                                      secrets: UnusedSecrets(), network: NetworkClient())
        model.saveNewMeetingHistory = true
        await model.createMeeting()
        let creation = Task { await model.createSubchat() }
        try await waitUntil { model.isLoading }
        model.activateProfile(.hr)
        let newStatus = model.status
        await repository.release(fail: true)
        await creation.value
        await model.loadLibrary()
        XCTAssertEqual(model.profile.id, .hr)
        XCTAssertEqual(model.chats.count, 1)
        XCTAssertEqual(model.status, newStatus)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(12)
        while !predicate() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Ожидание демопотока истекло")
                throw DemoError.invalidInput
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    func testDemoSendCancelAndSubchatIsolation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ConversationModel(profileID: .technical, repository: GRDBMeetingRepository(directory: directory),
                                      secrets: UnusedSecrets(), network: NetworkClient())
        model.draft = "Что такое транзакция?"
        model.send(configuration: ModelConfiguration())
        try await waitUntil { !model.streamingText.isEmpty }
        model.cancel()
        XCTAssertFalse(model.isGenerating)
        XCTAssertEqual(model.messages.last?.state, .cancelled)
        let firstChat = model.activeChatID
        let firstMessages = model.messages
        model.newChatTitle = "Второй вопрос"
        await model.createSubchat()
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertTrue(model.answer.isEmpty)
        model.draft = "Сохранить черновик до подтверждения"
        model.requestSwitch(firstChat)
        XCTAssertEqual(model.pendingChatID, firstChat)
        XCTAssertNotEqual(model.activeChatID, firstChat)
        model.confirmSwitch()
        try await waitUntil { model.activeChatID == firstChat && !model.isLoading }
        XCTAssertEqual(model.messages, firstMessages)
        XCTAssertTrue(model.draft.isEmpty)
    }

    @MainActor
    func testProfileChangeCancelsStreamAndClearsContext() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ConversationModel(profileID: .liveCoding, repository: GRDBMeetingRepository(directory: directory),
                                      secrets: UnusedSecrets(), network: NetworkClient())
        model.draft = "Пример Go"
        model.remoteConsent = true
        model.send(configuration: ModelConfiguration())
        try await waitUntil { !model.streamingText.isEmpty }
        model.activateProfile(.hr)
        await model.loadLibrary()
        XCTAssertEqual(model.profile.id, .hr)
        XCTAssertFalse(model.isGenerating)
        XCTAssertFalse(model.remoteConsent)
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertTrue(model.answer.isEmpty)
        XCTAssertTrue(model.draft.isEmpty)
    }

    @MainActor
    func testDemoCompletesWithoutKeyOrConsent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ConversationModel(profileID: .hr, repository: GRDBMeetingRepository(directory: directory),
                                      secrets: UnusedSecrets(), network: NetworkClient())
        model.draft = "Расскажи о себе"
        model.send(configuration: ModelConfiguration())
        try await waitUntil { !model.isGenerating }
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.messages.last?.state, .complete)
        XCTAssertEqual(model.messages.last?.isDemo, true)
        XCTAssertTrue(model.answer.contains("подтверждённые факты"))
    }
}

private struct TimedStreamingProvider: StreamingLLMProvider {
    func stream(_ request: GenerationRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.started(request.id))
                    try await Task.sleep(for: .milliseconds(25))
                    continuation.yield(.textDelta("Ответ"))
                    try await Task.sleep(for: .milliseconds(25))
                    continuation.yield(.completed)
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private struct OversizedStreamingProvider: StreamingLLMProvider {
    func stream(_ request: GenerationRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.started(request.id))
            continuation.yield(.textDelta("Принятая часть"))
            continuation.yield(.textDelta(String(repeating: "x", count: 256_001)))
            continuation.finish()
        }
    }
}

private actor DelayedChatRepository: MeetingRepository {
    let base: GRDBMeetingRepository
    private var gate: CheckedContinuation<Void, Never>?
    private var released = false
    private var shouldFail = false
    private(set) var saveCount = 0
    private(set) var deleteCount = 0
    var failAssistantWrites: Bool
    private var failUserWrites = false
    private var delayQuestion = false
    private var questionGate: CheckedContinuation<Void, Never>?
    var isQuestionWaiting: Bool { questionGate != nil }
    func delayQuestionWrite() { delayQuestion = true }
    func releaseQuestionWrite() { delayQuestion = false; questionGate?.resume(); questionGate = nil }
    func rejectUserWrites() { failUserWrites = true }
    func allowMessageWrites() { failAssistantWrites = false; failUserWrites = false }
    let delayDelete: Bool
    init(base: GRDBMeetingRepository, failAssistantWrites: Bool = false, delayDelete: Bool = false) {
        self.base = base; self.failAssistantWrites = failAssistantWrites; self.delayDelete = delayDelete
    }
    func release(fail: Bool) {
        shouldFail = fail; released = true; gate?.resume(); gate = nil
    }
    func saveSubchat(_ chat: Subchat) async throws {
        saveCount += 1
        if !released && !delayDelete { await withCheckedContinuation { gate = $0 } }
        if shouldFail { throw LocalStoreError.unavailable }
        try await base.saveSubchat(chat)
    }
    func profiles() async throws -> [ContextProfile] { try await base.profiles() }
    func saveProfile(_ profile: ContextProfile) async throws { try await base.saveProfile(profile) }
    func meetings(profile: ProfileID) async throws -> [Meeting] { try await base.meetings(profile: profile) }
    func createMeeting(_ meeting: Meeting, initialChat: Subchat) async throws { try await base.createMeeting(meeting, initialChat: initialChat) }
    func subchats(meetingID: UUID) async throws -> [Subchat] { try await base.subchats(meetingID: meetingID) }
    func deleteSubchat(id: UUID, meetingID: UUID) async throws {
        deleteCount += 1
        if !released && delayDelete { await withCheckedContinuation { gate = $0 } }
        if shouldFail { throw LocalStoreError.unavailable }
        try await base.deleteSubchat(id: id, meetingID: meetingID)
    }
    func messages(subchatID: UUID, meetingID: UUID) async throws -> [ChatMessage] { try await base.messages(subchatID: subchatID, meetingID: meetingID) }
    func saveMessage(_ message: ChatMessage, meetingID: UUID) async throws {
        if delayQuestion && message.role == .user { await withCheckedContinuation { questionGate = $0 } }
        if failUserWrites && message.role == .user { throw LocalStoreError.unavailable }
        if failAssistantWrites && message.role == .assistant { throw LocalStoreError.unavailable }
        try await base.saveMessage(message, meetingID: meetingID)
    }
    func deleteMeeting(id: UUID) async throws { try await base.deleteMeeting(id: id) }
    func exportMeeting(id: UUID) async throws -> Data { try await base.exportMeeting(id: id) }
}
