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
    var isBusy: Bool { isRunning || isBatchRunning }
    private var batchTask: Task<Void, Never>?
    private var batchID: UUID?
    private let secrets: any SecureSecretStore
    private let network: NetworkClient
    private let serviceFactory: ((ModelConfiguration) -> any TranscriptionService)?
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
         serviceFactory: ((ModelConfiguration) -> any TranscriptionService)? = nil) {
        self.secrets = secrets; self.network = network; self.serviceFactory = serviceFactory
    }

    func start(segment: AudioSegment, configuration: ModelConfiguration, vocabulary: [String]) {
        guard !isBusy else { return }
        perform(segment: segment, configuration: configuration, vocabulary: vocabulary, requestedLanguage: language, consent: remoteConsent)
    }

    // Снимок очереди: новые аудиофрагменты не добавляются без следующего действия пользователя.
    func startBatch(segments: [AudioSegment], configuration: ModelConfiguration, vocabulary: [String], remoteBatchConsent: Bool = false) {
        guard !isBusy else { return }
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

    private func perform(segment: AudioSegment, configuration: ModelConfiguration, vocabulary: [String],
                         requestedLanguage: TranscriptionLanguage, consent: Bool) {
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
        partialText = ""; editableText = ""; result = nil; completedRequest = nil
        status = configuration.mode == .demo ? "Демо: показываем пример расшифровки, звук не анализируется." : "Отправляется только выбранный аудиофрагмент."
        task = Task { [weak self] in
            do {
                var finalResult: TranscriptResult?
                for try await event in service.transcribe(segment, language: requestedLanguage, vocabulary: vocabulary) {
                    try Task.checkCancellation()
                    guard let self, activeID == id else { return }
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
                status = finalResult.isDemo ? "Учебный образец. Это не расшифровка вашей записи." : "Распознано. Исправьте термины перед использованием."
                isRunning = false; task = nil
            } catch {
                guard let self, activeID == id else { return }
                isRunning = false; task = nil
                partialText = ""
                status = error is CancellationError ? "Распознавание отменено" : ((error as? ProviderError)?.localizedDescription ?? "Распознавание не выполнено. Повторите вручную.")
            }
        }
    }
    func cancel() {
        batchID = nil; batchTask?.cancel(); batchTask = nil; isBatchRunning = false; remainingCount = 0
        activeID = nil; task?.cancel(); task = nil; isRunning = false; partialText = ""; status = "Распознавание отменено"
    }
    func reset() { cancel(); result = nil; editableText = ""; completedRequest = nil; remoteConsent = false; batchResults = [] }
}
