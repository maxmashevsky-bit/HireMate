import Foundation
import Observation
import CopilotCore

@MainActor @Observable
final class TranscriptionModel {
    var language: TranscriptionLanguage = .russian
    var remoteConsent = false
    var partialText = ""
    var editableText = ""
    var status = "Выберите аудиофрагмент в разделе «Звук»."
    private(set) var isRunning = false
    private(set) var result: TranscriptResult?
    private(set) var isBatchRunning = false
    private(set) var batchResults: [TranscriptResult] = []
    private(set) var remainingCount = 0
    private(set) var isLiveEnabled = false
    private(set) var liveQueuedCount = 0
    private(set) var liveDroppedCount = 0
    private(set) var suggestedQuestion: String?
    private(set) var transcriptEntries: [TranscriptEntry] = []
    private(set) var lastQueueWaitMilliseconds: Int?
    private(set) var lastFirstEventMilliseconds: Int?
    private(set) var lastRequestMilliseconds: Int?
    private(set) var lastRequestSucceeded: Bool?
    var includeRecentContext = false
    var compactedTranscriptCount: Int { timeline.compactedCount }
    var isBusy: Bool { isRunning || isBatchRunning }
    private var batchTask: Task<Void, Never>?
    private var batchID: UUID?
    private struct QueuedSegment {
        let segment: AudioSegment
        let enqueuedAt: ContinuousClock.Instant
    }
    private var liveQueue: [QueuedSegment] = []
    private var liveSeenIDs = Set<UUID>()
    private var liveTask: Task<Void, Never>?
    private var liveID: UUID?
    private struct LiveSettings {
        let configuration: ModelConfiguration
        let vocabulary: [String]
        let language: TranscriptionLanguage
        let consent: Bool
    }
    private var liveSettings: LiveSettings?
    private var timeline = TranscriptTimeline()
    private let secrets: any SecureSecretStore
    private let network: NetworkClient
    private let serviceFactory: ((ModelConfiguration) -> any TranscriptionService)?
    private let questionDetector: QuestionDetector
    private var task: Task<Void, Never>?
    private var activeID: UUID?
    private struct CompletedRequest: Equatable {
        let segment: UUID
        let language: TranscriptionLanguage
        let provider: String
        let model: String
        let endpoint: String
        let vocabulary: [String]
    }
    private var completedRequest: CompletedRequest?
    init(secrets: any SecureSecretStore, network: NetworkClient,
         serviceFactory: ((ModelConfiguration) -> any TranscriptionService)? = nil,
         questionDetector: QuestionDetector = QuestionDetector()) {
        self.secrets = secrets; self.network = network; self.serviceFactory = serviceFactory
        self.questionDetector = questionDetector
    }

    func start(segment: AudioSegment, configuration: ModelConfiguration, vocabulary: [String]) {
        guard !isBusy, !isLiveEnabled else { return }
        perform(segment: segment, configuration: configuration, vocabulary: vocabulary, requestedLanguage: language, consent: remoteConsent)
    }

    // Снимок очереди: новые аудиофрагменты не добавляются без следующего действия пользователя.
    func startBatch(segments: [AudioSegment], configuration: ModelConfiguration, vocabulary: [String], remoteBatchConsent: Bool = false) {
        guard !isBusy, !isLiveEnabled else { return }
        guard !segments.isEmpty, segments.count <= 6,
              segments.allSatisfy({ $0.duration.isFinite && $0.duration > 0 && $0.duration <= 60 && $0.samples.count <= 960_000 }) else {
            status = "Очередь допускает от 1 до 6 фрагментов длительностью до 60 секунд каждый."; return
        }
        guard configuration.mode == .demo || remoteBatchConsent else {
            status = "Подтвердите отправку всех фрагментов очереди выбранному провайдеру."; return
        }
        var seen = Set<UUID>()
        let queue = segments.filter { seen.insert($0.id).inserted }
        let id = UUID(); batchID = id; isBatchRunning = true
        batchResults = []; remainingCount = queue.count
        let requestedLanguage = language
        batchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if batchID == id { batchID = nil; isBatchRunning = false; remainingCount = 0; batchTask = nil }
            }
            for segment in queue {
                guard batchID == id, !Task.isCancelled else { return }
                perform(segment: segment, configuration: configuration, vocabulary: vocabulary,
                        requestedLanguage: requestedLanguage, consent: remoteBatchConsent)
                let current = task
                await current?.value
                guard batchID == id, !Task.isCancelled else { return }
                guard let result, result.segmentID == segment.id else { return }
                batchResults.append(result); remainingCount -= 1
            }
            status = "Очередь завершена. Результаты разделены по источникам; отправки в LLM не было."
        }
    }

    func selectBatchResult(_ selected: TranscriptResult) {
        guard !isBusy, batchResults.contains(where: { $0.id == selected.id }) else { return }
        result = selected; editableText = selected.text
    }

    @discardableResult
    func enableLive(configuration: ModelConfiguration, vocabulary: [String], remoteConsent: Bool = false) -> Bool {
        guard !isBusy, !isLiveEnabled else { return false }
        guard configuration.mode == .demo || remoteConsent else {
            status = "Подтвердите автоматическую отправку новых аудиофрагментов этому провайдеру."
            return false
        }
        if configuration.mode == .remote {
            do { try configuration.validate(forTranscription: true) }
            catch {
                status = (error as? ProviderError)?.localizedDescription ?? "Проверьте настройки распознавания."
                return false
            }
        }
        liveSettings = LiveSettings(configuration: configuration, vocabulary: vocabulary,
                                    language: language, consent: remoteConsent)
        liveQueue = []; liveSeenIDs = []; liveQueuedCount = 0; liveDroppedCount = 0
        liveID = UUID(); isLiveEnabled = true
        status = configuration.mode == .demo
            ? "Автоочередь включена в демо: звук не анализируется и не отправляется в сеть."
            : "Автоочередь включена: каждый новый фрагмент отправляется отдельно."
        return true
    }

    func enqueueLive(_ segment: AudioSegment) {
        guard isLiveEnabled, let settings = liveSettings,
              segment.duration.isFinite, segment.duration > 0, segment.duration <= 60,
              segment.samples.count <= 960_000, liveSeenIDs.insert(segment.id).inserted else { return }
        guard liveQueue.count < 5 else {
            liveDroppedCount += 1
            status = "Автоочередь заполнена. Новый фрагмент пропущен; остановите захват или дождитесь распознавания."
            return
        }
        liveQueue.append(QueuedSegment(segment: segment, enqueuedAt: ContinuousClock.now)); liveQueuedCount = liveQueue.count
        guard liveTask == nil, let id = liveID else { return }
        liveTask = Task { [weak self] in
            guard let self else { return }
            defer { if liveID == id { liveTask = nil } }
            while liveID == id, isLiveEnabled, !Task.isCancelled, !liveQueue.isEmpty {
                let queued = liveQueue.removeFirst(); liveQueuedCount = liveQueue.count
                let queueWait = Self.milliseconds(queued.enqueuedAt.duration(to: .now))
                perform(segment: queued.segment, configuration: settings.configuration, vocabulary: settings.vocabulary,
                        requestedLanguage: settings.language, consent: settings.consent, queueWaitMilliseconds: queueWait)
                let current = task
                await current?.value
                guard liveID == id, isLiveEnabled, !Task.isCancelled else { return }
                guard let result, result.segmentID == queued.segment.id else {
                    stopLive(clearStatus: false)
                    return
                }
                batchResults.append(result)
                if let candidate = questionDetector.candidate(from: result) { suggestedQuestion = candidate }
                if batchResults.count > 50 { batchResults.removeFirst(batchResults.count - 50) }
            }
        }
    }

    func disableLive() {
        guard isLiveEnabled else { return }
        stopLive(clearStatus: true)
    }

    func takeSuggestedQuestion() -> String? {
        defer { suggestedQuestion = nil }
        return suggestedQuestion
    }

    func dismissSuggestedQuestion() { suggestedQuestion = nil }

    func clearTranscript() {
        guard !isBusy else { return }
        timeline.clear(); transcriptEntries = []; suggestedQuestion = nil
    }

    func recentTranscriptContext(maximumCharacters: Int = 4_000) -> String {
        timeline.recentContext(maximumCharacters: maximumCharacters)
    }

    func contextForRequest() -> String {
        includeRecentContext ? timeline.contextWindow(maximumCharacters: 4_000) : ""
    }

    private func stopLive(clearStatus: Bool) {
        isLiveEnabled = false; liveID = nil; liveSettings = nil
        liveQueue = []; liveQueuedCount = 0; liveSeenIDs = []
        liveTask?.cancel(); liveTask = nil
        activeID = nil; task?.cancel(); task = nil; isRunning = false; partialText = ""
        if clearStatus { status = "Автоматическая очередь остановлена." }
    }

    private func perform(segment: AudioSegment, configuration: ModelConfiguration, vocabulary: [String],
                         requestedLanguage: TranscriptionLanguage, consent: Bool, queueWaitMilliseconds: Int? = nil) {
        if configuration.mode == .remote && !consent { status = "Подтвердите отправку выбранного аудиофрагмента."; return }
        let request = CompletedRequest(segment: segment.id, language: requestedLanguage,
                                       provider: configuration.mode.rawValue, model: configuration.transcriptionModel,
                                       endpoint: configuration.baseURL, vocabulary: vocabulary)
        guard completedRequest != request else { status = "Этот фрагмент уже распознан с выбранными параметрами. Текст можно отредактировать."; return }
        let service: any TranscriptionService
        if let serviceFactory { service = serviceFactory(configuration) }
        else if configuration.mode == .demo { service = FakeTranscriptionService() }
        else { service = RemoteTranscriptionService(configuration: configuration, secrets: secrets, network: network) }
        let id = UUID(); activeID = id; isRunning = true
        let startedAt = ContinuousClock.now
        lastQueueWaitMilliseconds = queueWaitMilliseconds
        lastFirstEventMilliseconds = nil; lastRequestMilliseconds = nil; lastRequestSucceeded = nil
        partialText = ""; editableText = ""; result = nil; completedRequest = nil
        status = configuration.mode == .demo ? "Демо: показываем пример расшифровки, звук не анализируется." : "Отправляется только выбранный аудиофрагмент."
        task = Task { [weak self] in
            do {
                var finalResult: TranscriptResult?
                for try await event in service.transcribe(segment, language: requestedLanguage, vocabulary: vocabulary) {
                    try Task.checkCancellation()
                    guard let self, activeID == id else { return }
                    if lastFirstEventMilliseconds == nil {
                        lastFirstEventMilliseconds = Self.milliseconds(startedAt.duration(to: .now))
                    }
                    switch event {
                    case .partial(let text): if finalResult == nil { partialText = text }
                    case .final(let result):
                        guard finalResult == nil else { continue }
                        guard result.segmentID == segment.id, result.source == segment.source,
                              !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            throw ProviderError.malformedResponse
                        }
                        finalResult = result
                        partialText = result.text
                    }
                }
                guard let self, activeID == id else { return }
                guard let finalResult else { throw ProviderError.incompleteStream }
                completedRequest = request
                result = finalResult; editableText = finalResult.text; partialText = ""
                timeline.append(finalResult); transcriptEntries = timeline.entries
                if let candidate = questionDetector.candidate(from: finalResult) { suggestedQuestion = candidate }
                status = finalResult.isDemo ? "Учебный образец. Это не расшифровка вашей записи." : "Распознано. Исправьте термины перед использованием."
                lastRequestMilliseconds = Self.milliseconds(startedAt.duration(to: .now)); lastRequestSucceeded = true
                isRunning = false; task = nil
            } catch {
                guard let self, activeID == id else { return }
                lastRequestMilliseconds = Self.milliseconds(startedAt.duration(to: .now)); lastRequestSucceeded = false
                isRunning = false; task = nil
                partialText = ""
                status = error is CancellationError ? "Распознавание отменено" : ((error as? ProviderError)?.localizedDescription ?? "Распознавание не выполнено. Повторите вручную.")
            }
        }
    }
    private static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        let value = components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
        return Int(min(Int64(Int.max), max(0, value)))
    }
    func cancel() {
        if isLiveEnabled { stopLive(clearStatus: false) }
        batchID = nil; batchTask?.cancel(); batchTask = nil; isBatchRunning = false; remainingCount = 0
        activeID = nil; task?.cancel(); task = nil; isRunning = false; partialText = ""; status = "Распознавание отменено"
    }
    func clearLatencyMetrics() {
        lastQueueWaitMilliseconds = nil
        lastFirstEventMilliseconds = nil
        lastRequestMilliseconds = nil
        lastRequestSucceeded = nil
    }
    func reset() { cancel(); result = nil; editableText = ""; completedRequest = nil; remoteConsent = false; batchResults = []; liveDroppedCount = 0; suggestedQuestion = nil; timeline.clear(); transcriptEntries = []; includeRecentContext = false; clearLatencyMetrics() }
}
