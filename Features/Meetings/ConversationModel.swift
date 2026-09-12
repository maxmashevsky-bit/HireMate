import Foundation
import Observation
import CopilotCore

@MainActor @Observable
final class ConversationModel {
    var draft = ""
    private(set) var attachment: ImageAttachment?
    @discardableResult
    func attach(_ image: ImageAttachment) -> Bool {
        guard !isGenerating, !isLoading else { return false }
        attachment = image; status = "Просмотренный снимок приложен только к следующему вопросу."
        return true
    }
    func removeAttachment() { attachment = nil }
    var remoteConsent = false
    var onCompletedAnswer: ((String) -> Void)?
    var status = "Демонстрация без сети"
    var newMeetingTitle = "Новая встреча"
    var saveNewMeetingHistory = false
    var newChatTitle = "Новый поддиалог"
    var pendingChatID: UUID?
    private(set) var profiles = ProfileID.allCases.map { ContextProfile(id: $0) }
    private(set) var savedMeetings: [Meeting] = []
    private(set) var meeting: Meeting
    private(set) var chats: [Subchat]
    private(set) var activeChatID: UUID
    private(set) var messages: [ChatMessage] = []
    private(set) var streamingText = ""
    private(set) var isGenerating = false
    private(set) var isLoading = false
    private(set) var contextWasTruncated = false
    private(set) var estimatedTokens = 0
    private(set) var actualInputTokens: Int?
    private(set) var actualOutputTokens: Int?
    private(set) var includedTranscriptCharacters = 0
    private let repository: any MeetingRepository
    private let secrets: any SecureSecretStore
    private let network: NetworkClient
    private let assembler: any ContextAssembler
    private let noteSearch: (any NoteSearchService)?
    private var retrieval: Task<Void, Never>?
    private var retrievalID = UUID()
    private(set) var retrievedNotes: [NoteFragment] = []
    private(set) var includedNoteIDs: [String] = []
    private var memory: [UUID: [ChatMessage]] = [:]
    private var generation: Task<Void, Never>?
    private struct GenerationWork {
        let meetingID: UUID
        let chatID: UUID
        let task: Task<Void, Never>
    }
    private var generationWork: [UUID: GenerationWork] = [:]
    private var requestID: UUID?
    private var navigationID = UUID()
    private struct MessageWrite {
        let answer: ChatMessage
        let meetingID: UUID
    }
    private var messageWrites: [UUID: Task<Void, Never>] = [:]
    private var failedMessageWrites: [UUID: MessageWrite] = [:]
    var unsavedMessageCount: Int { failedMessageWrites.count }
    var isSavingMessages: Bool { !messageWrites.isEmpty }

    init(profileID: ProfileID, repository: any MeetingRepository, secrets: any SecureSecretStore,
         network: NetworkClient, assembler: any ContextAssembler = BoundedContextAssembler(), noteSearch: (any NoteSearchService)? = nil) {
        self.repository = repository; self.secrets = secrets; self.network = network; self.assembler = assembler; self.noteSearch = noteSearch
        let meeting = Meeting(profileID: profileID, title: "Демонстрация", isEphemeral: true)
        let chat = Subchat(meetingID: meeting.id, title: "Основной")
        self.meeting = meeting; chats = [chat]; activeChatID = chat.id
    }
    var profile: ContextProfile { profiles.first { $0.id == meeting.profileID } ?? ContextProfile(id: meeting.profileID) }
    var answer: String { isGenerating ? streamingText : (messages.last(where: { $0.role == .assistant })?.content ?? "") }

    func loadLibrary() async {
        let id = navigationID; let profile = meeting.profileID
        do {
            let loaded = try await repository.profiles()
            let meetings = try await repository.meetings(profile: profile)
            guard navigationID == id else { return }
            self.profiles = loaded; savedMeetings = meetings
        } catch { status = "Не удалось открыть локальную библиотеку. Текущий разговор остаётся в памяти." }
    }
    func activateProfile(_ id: ProfileID) {
        guard meeting.profileID != id else { return }
        cancel()
        navigationID = UUID(); isLoading = false
        let next = Meeting(profileID: id, title: "Разговор без сохранения", isEphemeral: true)
        activate(next, chats: [Subchat(meetingID: next.id, title: "Основной")])
        savedMeetings = []; remoteConsent = false
        Task { await loadLibrary() }
    }
    func createMeeting() async {
        guard !isLoading else { return }
        cancel()
        let title = String(newMeetingTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !title.isEmpty else { status = "Введите название встречи."; return }
        let next = Meeting(profileID: meeting.profileID, title: title, isEphemeral: !saveNewMeetingHistory)
        let chat = Subchat(meetingID: next.id, title: "Основной")
        let navigation = UUID(); navigationID = navigation; isLoading = true
        defer { if navigationID == navigation { isLoading = false } }
        do {
            if !next.isEphemeral { try await repository.createMeeting(next, initialChat: chat) }
            guard navigationID == navigation else { return }
            activate(next, chats: [chat])
            await loadLibrary()
        } catch { status = "Не удалось сохранить встречу. Новый разговор не создан." }
    }
    func open(_ selected: Meeting) async {
        guard selected.profileID == meeting.profileID, !isLoading else { return }
        cancel()
        let navigation = UUID(); navigationID = navigation; isLoading = true
        defer { if navigationID == navigation { isLoading = false } }
        do {
            let chats = try await repository.subchats(meetingID: selected.id)
            guard let first = chats.first else { throw LocalStoreError.invalidData }
            let history = try await repository.messages(subchatID: first.id, meetingID: selected.id)
            guard navigationID == navigation else { return }
            activate(selected, chats: chats); messages = history
        } catch { status = "Не удалось открыть встречу. Текущий разговор не изменён." }
    }
    func createSubchat() async {
        guard !isLoading else { return }
        cancel()
        let title = String(newChatTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !title.isEmpty else { status = "Введите название поддиалога."; return }
        let chat = Subchat(meetingID: meeting.id, title: title)
        let meetingID = meeting.id
        let navigation = UUID(); navigationID = navigation; isLoading = true
        let originalDraft = draft; let originalAttachment = attachment?.id
        defer { if navigationID == navigation { isLoading = false } }
        do {
            if !meeting.isEphemeral { try await repository.saveSubchat(chat) }
            guard meeting.id == meetingID, navigationID == navigation else { return }
            memory[activeChatID] = messages
            chats.append(chat); activeChatID = chat.id; messages = []; streamingText = ""
            if draft == originalDraft { draft = "" }
            if attachment?.id == originalAttachment { attachment = nil }
            pendingChatID = nil; retrievedNotes = []; includedNoteIDs = []
            contextWasTruncated = false; estimatedTokens = 0
            actualInputTokens = nil; actualOutputTokens = nil
            status = "Поддиалог создан"
        } catch {
            if navigationID == navigation { status = "Поддиалог не сохранён. Текущий разговор и черновик сохранены." }
        }
    }
    func requestSwitch(_ chatID: UUID) {
        guard !isLoading, chatID != activeChatID, chats.contains(where: { $0.id == chatID }) else { return }
        if attachment != nil || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pendingChatID = chatID }
        else { Task { await switchChat(chatID) } }
    }
    func confirmSwitch() {
        guard let id = pendingChatID else { return }
        pendingChatID = nil
        Task { await switchChat(id) }
    }
    private func switchChat(_ id: UUID) async {
        guard chats.contains(where: { $0.id == id && $0.meetingID == meeting.id }), !isLoading else { return }
        cancel(); memory[activeChatID] = messages
        let parent = meeting; let navigation = UUID(); navigationID = navigation; isLoading = true
        defer { if navigationID == navigation { isLoading = false } }
        do {
            let loaded: [ChatMessage]
            if let cached = memory[id] { loaded = cached }
            else if parent.isEphemeral { loaded = [] }
            else { loaded = try await repository.messages(subchatID: id, meetingID: parent.id) }
            guard navigationID == navigation else { return }
            activeChatID = id; messages = loaded; retrievedNotes = []; includedNoteIDs = []; attachment = nil; draft = ""; streamingText = ""
        } catch { if navigationID == navigation { status = "Не удалось открыть поддиалог." } }
    }
    func renameActiveChat(_ name: String) async {
        guard !isLoading, let index = chats.firstIndex(where: { $0.id == activeChatID }) else { return }
        var chat = chats[index]
        chat.title = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)); chat.updatedAt = Date()
        guard !chat.title.isEmpty else { return }
        let navigation = UUID(); navigationID = navigation; isLoading = true
        defer { if navigationID == navigation { isLoading = false } }
        do {
            if !meeting.isEphemeral { try await repository.saveSubchat(chat) }
            guard navigationID == navigation else { return }
            if let current = chats.firstIndex(where: { $0.id == chat.id }) { chats[current] = chat }
        } catch { if navigationID == navigation { status = "Название не сохранено." } }
    }
    func deleteActiveChat() async {
        guard !isLoading else { return }
        guard chats.count > 1, let next = chats.first(where: { $0.id != activeChatID }) else {
            status = "Последний поддиалог нельзя удалить."; return
        }
        cancel()
        let deleted = activeChatID; let parent = meeting.id
        let navigation = UUID(); navigationID = navigation; isLoading = true
        defer { if navigationID == navigation { isLoading = false } }
        do {
            // Сначала читаем следующий диалог: ошибка чтения не удалит текущий.
            await waitForGenerationWrites(meetingID: parent, chatID: deleted)
            await flushPendingMessages()
            guard navigationID == navigation else { return }
            let loaded: [ChatMessage]
            if let cached = memory[next.id] { loaded = cached }
            else if meeting.isEphemeral { loaded = [] }
            else { loaded = try await repository.messages(subchatID: next.id, meetingID: parent) }
            guard navigationID == navigation else { return }
            if !meeting.isEphemeral { try await repository.deleteSubchat(id: deleted, meetingID: parent) }
            guard meeting.id == parent, navigationID == navigation else { return }
            chats.removeAll { $0.id == deleted }; memory.removeValue(forKey: deleted)
            failedMessageWrites = failedMessageWrites.filter { $0.value.answer.subchatID != deleted }
            activeChatID = next.id; messages = loaded; draft = ""; attachment = nil
            pendingChatID = nil; retrievedNotes = []; includedNoteIDs = []; streamingText = ""
            status = "Поддиалог удалён"
        } catch { if navigationID == navigation { status = "Поддиалог не удалён." } }
    }
    func deleteMeeting(_ selected: Meeting) async {
        guard !isLoading, selected.profileID == meeting.profileID else { return }
        if meeting.id == selected.id { cancel() }
        let navigation = UUID(); navigationID = navigation; isLoading = true
        defer { if navigationID == navigation { isLoading = false } }
        do {
            await waitForGenerationWrites(meetingID: selected.id)
            await flushPendingMessages()
            guard navigationID == navigation else { return }
            try await repository.deleteMeeting(id: selected.id)
            guard navigationID == navigation else { return }
            savedMeetings.removeAll { $0.id == selected.id }
            failedMessageWrites = failedMessageWrites.filter { $0.value.meetingID != selected.id }
            if meeting.id == selected.id {
                let next = Meeting(profileID: selected.profileID, title: "Разговор без сохранения", isEphemeral: true)
                activate(next, chats: [Subchat(meetingID: next.id, title: "Основной")])
            }
        } catch { if navigationID == navigation { status = "Встреча не удалена." } }
    }
    func saveProfile(_ profile: ContextProfile) async throws {
        var next = profile; next.updatedAt = Date()
        try await repository.saveProfile(next)
        if let index = profiles.firstIndex(where: { $0.id == next.id }) { profiles[index] = next }
    }

    func send(configuration: ModelConfiguration, action: QuickAction? = nil, transcriptContext: String = "") {
        guard !isGenerating, !isLoading else { return }
        retrievedNotes = []; includedNoteIDs = []; includedTranscriptCharacters = 0
        guard profile.usesNotes, let noteSearch else { sendPrepared(configuration: configuration, action: action, notes: [], transcriptContext: transcriptContext); return }
        let profile = profile; let query = draft; let imageID = attachment?.id; let navigation = navigationID
        let id = UUID(); retrievalID = id; isLoading = true; status = "Поиск разрешённых заметок на Mac…"
        retrieval = Task { [weak self] in
            guard let self else { return }
            defer { if retrievalID == id { isLoading = false; retrieval = nil } }
            do {
                let notes = try await noteSearch.retrieve(query: query, profile: profile.id, tags: profile.selectedNoteTags ?? [], limit: 4)
                try Task.checkCancellation()
                guard retrievalID == id, navigationID == navigation, draft == query, attachment?.id == imageID else {
                    if retrievalID == id { status = "Вопрос изменился. Запустите отправку заново." }; return
                }
                isLoading = false; retrievedNotes = notes
                sendPrepared(configuration: configuration, action: action, notes: notes, transcriptContext: transcriptContext)
            } catch { if retrievalID == id { status = "Поиск заметок не завершён. Запрос в AI не отправлен." } }
        }
    }
    private func sendPrepared(configuration: ModelConfiguration, action: QuickAction?, notes: [NoteFragment], transcriptContext: String) {
        guard !isGenerating, !isLoading else { return }
        if let action {
            guard action.isValid, action.profileID == meeting.profileID else { status = "Действие относится к другому профилю."; return }
            guard draft.count <= 4_000 else { status = "Сократите вопрос до 4000 символов."; return }
        } else { guard InputValidation.canSend(draft) else { return } }
        guard configuration.mode == .demo || remoteConsent else { status = "Подтвердите отправку текста и активного контекста выбранному API."; return }
        do {
            let includedImage = (action == nil || action?.includeScreenshot == true) ? attachment : nil
            if action?.includeScreenshot == true && includedImage == nil {
                status = "Сначала сделайте, просмотрите и приложите снимок в разделе «Снимок экрана»."; return
            }
            let question = draft + (action.map { "\n\nБыстрое действие: \($0.name).\n\($0.prompt)\nСтиль: \($0.outputStyle)" } ?? "")
            var budgetConfiguration = configuration
            if includedImage != nil {
                guard configuration.mode == .demo || configuration.visionEnabled else { throw ProviderError.unsupportedFeature }
                // Запас под vision приблизительный: точная тарификация зависит от сервера.
                budgetConfiguration.maxContextTokens -= 4_096
            }
            let textPrompt = try assembler.assemble(profile: profile, history: messages, subchatID: activeChatID, question: question,
                                                    configuration: budgetConfiguration, notes: notes, transcriptContext: transcriptContext)
            let prompt = GenerationRequest(id: textPrompt.id, profileID: textPrompt.profileID, messages: textPrompt.messages,
                currentQuestion: textPrompt.currentQuestion, wasTruncated: textPrompt.wasTruncated,
                estimatedInputTokens: textPrompt.estimatedInputTokens + (includedImage == nil ? 0 : 4_096), attachments: includedImage.map { [$0] } ?? [],
                includedNoteIDs: textPrompt.includedNoteIDs, includedTranscriptCharacters: textPrompt.includedTranscriptCharacters)
            if configuration.mode == .remote { try configuration.validate() }
            includedNoteIDs = prompt.includedNoteIDs
            includedTranscriptCharacters = textPrompt.includedTranscriptCharacters
            contextWasTruncated = prompt.wasTruncated; estimatedTokens = prompt.estimatedInputTokens
            actualInputTokens = nil; actualOutputTokens = nil
            let user = ChatMessage(subchatID: activeChatID, role: .user, content: question + (includedImage == nil ? "" : "\n\n[Приложен просмотренный снимок; изображение не сохраняется в истории.]"), isDemo: configuration.mode == .demo)
            messages.append(user); if includedImage != nil { attachment = nil }; draft = ""; streamingText = ""; isGenerating = true
            requestID = prompt.id
            let parent = meeting
            let provider: any StreamingLLMProvider = configuration.mode == .demo ? FakeStreamingProvider()
                : OpenAICompatibleLLMProvider(configuration: configuration, secrets: secrets, network: network)
            status = configuration.mode == .demo ? "Учебный образец без анализа вопроса" : "Запрос отправляется выбранному API"
            let task = Task { [weak self] in
                guard let self else { return }
                defer { generationWork.removeValue(forKey: prompt.id) }
                var savedUserMessage = parent.isEphemeral
                do {
                    if !parent.isEphemeral { try await repository.saveMessage(user, meetingID: parent.id) }
                    savedUserMessage = true
                    try Task.checkCancellation()
                    guard requestID == prompt.id else { return }
                    var completed = false
                    for try await event in provider.stream(prompt) {
                        try Task.checkCancellation()
                        guard requestID == prompt.id else { return }
                        switch event {
                        case .started: break
                        case .textDelta(let text): streamingText += text
                        case .usage(let input, let output): actualInputTokens = input; actualOutputTokens = output
                        case .completed: completed = true
                        }
                    }
                    guard requestID == prompt.id else { return }
                    finish(state: completed ? .complete : .failed, demo: configuration.mode == .demo)
                    status = completed ? (configuration.mode == .demo ? "Демонстрационный образец завершён" : "Ответ завершён") : "Поток оборвался"
                } catch {
                    if !savedUserMessage { failedMessageWrites[user.id] = MessageWrite(answer: user, meetingID: parent.id) }
                    guard requestID == prompt.id else { return }
                    finish(state: error is CancellationError ? .cancelled : .failed, demo: configuration.mode == .demo)
                    status = (error as? ProviderError)?.localizedDescription ?? (error is CancellationError ? "Ответ остановлен" : "Не удалось сохранить или получить ответ.")
                }
            }
            generation = task
            generationWork[prompt.id] = GenerationWork(meetingID: parent.id, chatID: user.subchatID, task: task)
        } catch { status = (error as? ProviderError)?.localizedDescription ?? "Не удалось подготовить вопрос." }
    }
    func cancel() {
        if retrieval != nil { retrieval?.cancel(); retrieval = nil; retrievalID = UUID(); isLoading = false; status = "Подготовка запроса отменена" }
        guard isGenerating else { return }
        generation?.cancel()
        finish(state: .cancelled, demo: messages.last?.isDemo ?? true)
        status = "Ответ остановлен. Полученный текст сохранён в текущем поддиалоге."
    }
    private func finish(state: MessageState, demo: Bool) {
        if !streamingText.isEmpty {
            let answer = ChatMessage(subchatID: activeChatID, role: .assistant, content: streamingText, state: state, isDemo: demo)
            messages.append(answer)
            if state == .complete { onCompletedAnswer?(answer.content) }
            if !meeting.isEphemeral {
                let parent = meeting.id
                queueMessageWrite(MessageWrite(answer: answer, meetingID: parent))
            }
        }
        memory[activeChatID] = messages
        streamingText = ""; isGenerating = false; requestID = nil; generation = nil
    }
    private func queueMessageWrite(_ write: MessageWrite) {
        let id = write.answer.id
        guard messageWrites[id] == nil else { return }
        messageWrites[id] = Task { [weak self, repository] in
            do {
                try await repository.saveMessage(write.answer, meetingID: write.meetingID)
                self?.failedMessageWrites.removeValue(forKey: id)
            } catch {
                self?.failedMessageWrites[id] = write
                if self?.meeting.id == write.meetingID {
                    self?.status = "Ответ остался в памяти. Повторите сохранение или экспортируйте разговор перед выходом."
                }
            }
            self?.messageWrites.removeValue(forKey: id)
        }
    }
    func flushPendingMessages() async {
        while let task = messageWrites.values.first { await task.value }
    }
    func retryUnsavedMessages() async {
        await flushPendingMessages()
        for write in Array(failedMessageWrites.values) { queueMessageWrite(write) }
        await flushPendingMessages()
    }
    func finishForTermination() async {
        cancel()
        for work in Array(generationWork.values) { await work.task.value }
        await retryUnsavedMessages()
    }
    private func waitForGenerationWrites(meetingID: UUID, chatID: UUID? = nil) async {
        let pending = generationWork.values.filter { $0.meetingID == meetingID && (chatID == nil || $0.chatID == chatID) }
        for work in pending { await work.task.value }
    }
    private func activate(_ next: Meeting, chats: [Subchat]) {
        guard let first = chats.first else { return }
        meeting = next; self.chats = chats; activeChatID = first.id
        messages = []; memory = [:]; attachment = nil; draft = ""; streamingText = ""; remoteConsent = false
        pendingChatID = nil
        retrievedNotes = []; includedNoteIDs = []
        contextWasTruncated = false; status = next.isEphemeral ? "История только в памяти" : "Встреча сохраняется локально"
        includedTranscriptCharacters = 0
    }
    func exportCurrent(markdown: Bool = false) async throws -> Data {
        // Текущие сообщения берутся из памяти: экспорт не теряет ответ при сбое записи на диск.
        let snapshotMeeting = meeting; let snapshotChats = chats
        var history = memory; history[activeChatID] = messages
        if !snapshotMeeting.isEphemeral {
            for chat in snapshotChats where history[chat.id] == nil {
                history[chat.id] = try await repository.messages(subchatID: chat.id, meetingID: snapshotMeeting.id)
            }
        }
        let archive = MeetingArchive(meeting: snapshotMeeting, subchats: snapshotChats, messages: snapshotChats.flatMap { history[$0.id] ?? [] })
        if markdown { return Data(archive.markdown().utf8) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }
}
