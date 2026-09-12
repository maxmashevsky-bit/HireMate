import XCTest
import CopilotCore

@MainActor
private struct NoTranscriptionSecrets: SecureSecretStore {
    func save(_ secret: String) throws { XCTFail("Демо не сохраняет ключ") }
    func read() throws -> String? { XCTFail("Демо не читает ключ"); return nil }
    func delete() throws { XCTFail("Демо не удаляет ключ") }
}

final class TranscriptionFlowTests: XCTestCase {
    @MainActor
    func testOnlyFinalSystemTranscriptSuggestsQuestion() async throws {
        var text = "Как устроен scheduler Go"
        let model = TranscriptionModel(secrets: NoTranscriptionSecrets(), network: NetworkClient(), serviceFactory: { _ in
            ScriptedTranscription(text: text)
        })
        let system = AudioSegment(source: .system, startedAt: 0, samples: [0.1], reason: "Тест")
        model.start(segment: system, configuration: ModelConfiguration(), vocabulary: [])
        try await waitForResult(model)
        XCTAssertEqual(model.takeSuggestedQuestion(), text)
        XCTAssertNil(model.suggestedQuestion)

        text = "Почему я выбрал Go?"
        let microphone = AudioSegment(source: .microphone, startedAt: 1, samples: [0.1], reason: "Тест")
        model.start(segment: microphone, configuration: ModelConfiguration(), vocabulary: [])
        try await waitForResult(model)
        XCTAssertNil(model.suggestedQuestion)
    }
    @MainActor
    func testLiveQueueProcessesUniqueSegmentsInOrderAndKeepsSources() async throws {
        var calls = 0
        let model = TranscriptionModel(secrets: NoTranscriptionSecrets(), network: NetworkClient(), serviceFactory: { _ in
            calls += 1; return ScriptedTranscription()
        })
        XCTAssertTrue(model.enableLive(configuration: ModelConfiguration(), vocabulary: ["Go"]))
        let mic = AudioSegment(source: .microphone, startedAt: 1, samples: [0.1], reason: "Тест")
        let system = AudioSegment(source: .system, startedAt: 2, samples: [0.1], reason: "Тест")
        model.enqueueLive(mic); model.enqueueLive(mic); model.enqueueLive(system)
        try await eventually { model.batchResults.count == 2 && !model.isRunning }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(model.batchResults.map(\.source), [.microphone, .system])
        XCTAssertTrue(model.isLiveEnabled)
        model.disableLive()
        XCTAssertFalse(model.isLiveEnabled)
    }

    @MainActor
    func testLiveQueueStopsOnFailureAndDiscardsPendingWork() async throws {
        var calls = 0
        let model = TranscriptionModel(secrets: NoTranscriptionSecrets(), network: NetworkClient(), serviceFactory: { _ in
            calls += 1; return ScriptedTranscription(failAfterFinal: true)
        })
        XCTAssertTrue(model.enableLive(configuration: ModelConfiguration(), vocabulary: []))
        for index in 0..<3 {
            model.enqueueLive(AudioSegment(source: .system, startedAt: Double(index), samples: [0.1], reason: "Тест"))
        }
        try await eventually { !model.isLiveEnabled }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.liveQueuedCount, 0)
        XCTAssertTrue(model.batchResults.isEmpty)
    }

    @MainActor
    func testLiveQueueBoundsPendingWorkAndCancelRejectsLateResult() async throws {
        let model = TranscriptionModel(secrets: NoTranscriptionSecrets(), network: NetworkClient(), serviceFactory: { _ in
            FakeTranscriptionService()
        })
        XCTAssertTrue(model.enableLive(configuration: ModelConfiguration(), vocabulary: []))
        model.enqueueLive(AudioSegment(source: .system, startedAt: 0, samples: [0.1], reason: "Тест"))
        try await eventually { model.isRunning }
        for index in 1...6 {
            model.enqueueLive(AudioSegment(source: .system, startedAt: Double(index), samples: [0.1], reason: "Тест"))
        }
        XCTAssertEqual(model.liveQueuedCount, 5)
        XCTAssertEqual(model.liveDroppedCount, 1)
        model.disableLive()
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertNil(model.result)
        XCTAssertTrue(model.batchResults.isEmpty)
    }

    @MainActor
    func testLiveRemoteModeNeedsDedicatedConsentAndValidConfiguration() {
        let model = TranscriptionModel(secrets: NoTranscriptionSecrets(), network: NetworkClient(), serviceFactory: { _ in
            XCTFail("Фрагменты не добавлялись"); return ScriptedTranscription()
        })
        var remote = ModelConfiguration(); remote.mode = .remote
        remote.baseURL = "https://example.com/v1"; remote.transcriptionModel = "stt-test"
        model.remoteConsent = true
        XCTAssertFalse(model.enableLive(configuration: remote, vocabulary: []))
        XCTAssertTrue(model.enableLive(configuration: remote, vocabulary: [], remoteConsent: true))
        model.disableLive()
        remote.baseURL = "http://example.com/v1"
        XCTAssertFalse(model.enableLive(configuration: remote, vocabulary: [], remoteConsent: true))
    }
    @MainActor
    func testBatchKeepsSourcesAndDeduplicatesSegments() async throws {
        var calls = 0
        let model = TranscriptionModel(secrets: NoTranscriptionSecrets(), network: NetworkClient(), serviceFactory: { _ in
            calls += 1; return ScriptedTranscription()
        })
        let mic = AudioSegment(source: .microphone, startedAt: 0, samples: [0.1], reason: "Тест")
        let system = AudioSegment(source: .system, startedAt: 0, samples: [0.1], reason: "Тест")
        model.startBatch(segments: [mic, mic, system], configuration: ModelConfiguration(), vocabulary: [])
        model.start(segment: system, configuration: ModelConfiguration(), vocabulary: [])
        try await waitForResult(model)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(model.batchResults.map(\.source), [.microphone, .system])
        XCTAssertEqual(model.remainingCount, 0)
        model.reset()
        XCTAssertTrue(model.batchResults.isEmpty)
    }

    @MainActor
    func testBatchStopsOnFailureWithoutSendingNextSegment() async throws {
        var calls = 0
        let model = TranscriptionModel(secrets: NoTranscriptionSecrets(), network: NetworkClient(), serviceFactory: { _ in
            calls += 1; return ScriptedTranscription(failAfterFinal: true)
        })
        let segments = (0..<3).map { AudioSegment(source: .system, startedAt: Double($0), samples: [0.1], reason: "Тест") }
        model.startBatch(segments: segments, configuration: ModelConfiguration(), vocabulary: [])
        try await waitForResult(model)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(model.batchResults.isEmpty)
    }

    @MainActor
    func testBatchCancelPreventsFurtherRequestsAndLateResults() async throws {
        var calls = 0
        let model = TranscriptionModel(secrets: NoTranscriptionSecrets(), network: NetworkClient(), serviceFactory: { _ in
            calls += 1; return FakeTranscriptionService()
        })
        let segments = (0..<3).map { AudioSegment(source: .system, startedAt: Double($0), samples: [0.1], reason: "Тест") }
        model.startBatch(segments: segments, configuration: ModelConfiguration(), vocabulary: [])
        try await Task.sleep(for: .milliseconds(100))
        model.cancel()
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(model.batchResults.isEmpty)
        XCTAssertNil(model.result)
    }

    @MainActor
    func testBatchRejectsMissingConsentAndExcessCount() {
        let model = TranscriptionModel(secrets: NoTranscriptionSecrets(), network: NetworkClient(), serviceFactory: { _ in
            XCTFail("Недопустимая очередь не должна открывать провайдер"); return ScriptedTranscription()
        })
        let segment = AudioSegment(source: .system, startedAt: 0, samples: [0.1], reason: "Тест")
        var remote = ModelConfiguration(); remote.mode = .remote
        model.remoteConsent = true // Согласие на один фрагмент не разрешает всю очередь.
        model.startBatch(segments: [segment], configuration: remote, vocabulary: [])
        XCTAssertFalse(model.isBusy)
        model.startBatch(segments: Array(repeating: segment, count: 7), configuration: ModelConfiguration(), vocabulary: [])
        XCTAssertFalse(model.isBusy)
    }
    @MainActor
    func testFinalFollowedByErrorDoesNotBlockRetry() async throws {
        var shouldFail = true
        let model = TranscriptionModel(secrets: NoTranscriptionSecrets(), network: NetworkClient(), serviceFactory: { _ in
            ScriptedTranscription(failAfterFinal: shouldFail)
        })
        let segment = AudioSegment(source: .system, startedAt: 0, samples: [0.1], reason: "Тест")
        model.start(segment: segment, configuration: ModelConfiguration(), vocabulary: [])
        try await waitForResult(model)
        XCTAssertNil(model.result)
        XCTAssertTrue(model.editableText.isEmpty)
        XCTAssertTrue(model.partialText.isEmpty)
        shouldFail = false
        model.start(segment: segment, configuration: ModelConfiguration(), vocabulary: [])
        XCTAssertTrue(model.isRunning)
        try await waitForResult(model)
        XCTAssertEqual(model.result?.source, .system)
        XCTAssertEqual(model.editableText, "Финальный текст")
    }

    @MainActor
    func testWrongAudioSourceIsRejected() async throws {
        let model = TranscriptionModel(secrets: NoTranscriptionSecrets(), network: NetworkClient(), serviceFactory: { _ in
            ScriptedTranscription(wrongSource: true)
        })
        let segment = AudioSegment(source: .microphone, startedAt: 0, samples: [0.1], reason: "Тест")
        model.start(segment: segment, configuration: ModelConfiguration(), vocabulary: [])
        try await waitForResult(model)
        XCTAssertNil(model.result)
        XCTAssertTrue(model.editableText.isEmpty)
    }

    @MainActor
    func testLatePartialAndDuplicateFinalDoNotReplaceFinal() async throws {
        let model = TranscriptionModel(secrets: NoTranscriptionSecrets(), network: NetworkClient(), serviceFactory: { _ in
            ScriptedTranscription()
        })
        let segment = AudioSegment(source: .microphone, startedAt: 0, samples: [0.1], reason: "Тест")
        model.start(segment: segment, configuration: ModelConfiguration(), vocabulary: [])
        try await waitForResult(model)
        XCTAssertEqual(model.result?.source, .microphone)
        XCTAssertEqual(model.editableText, "Финальный текст")
        XCTAssertTrue(model.partialText.isEmpty)
    }
    @MainActor
    private func waitForResult(_ model: TranscriptionModel) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        while model.isBusy {
            guard ContinuousClock.now < deadline else { throw LocalStoreError.unavailable }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    @MainActor
    private func eventually(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw LocalStoreError.unavailable }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    @MainActor
    func testLanguageChangeAllowsSameSegmentAgain() async throws {
        let model = TranscriptionModel(secrets: NoTranscriptionSecrets(), network: NetworkClient())
        let segment = AudioSegment(source: .microphone, startedAt: 0, samples: [0.1], reason: "Тест")
        model.start(segment: segment, configuration: ModelConfiguration(), vocabulary: [])
        try await waitForResult(model)
        XCTAssertTrue(model.editableText.contains("Демонстрационный"))
        model.start(segment: segment, configuration: ModelConfiguration(), vocabulary: [])
        XCTAssertFalse(model.isRunning)
        model.language = .english
        model.start(segment: segment, configuration: ModelConfiguration(), vocabulary: [])
        XCTAssertTrue(model.isRunning)
        try await waitForResult(model)
        XCTAssertTrue(model.editableText.contains("Demo question"))
    }
    @MainActor
    func testResetCancelsOldResultAndAllowsRetry() async throws {
        let model = TranscriptionModel(secrets: NoTranscriptionSecrets(), network: NetworkClient())
        let segment = AudioSegment(source: .system, startedAt: 0, samples: [0.1], reason: "Тест")
        model.start(segment: segment, configuration: ModelConfiguration(), vocabulary: [])
        model.reset()
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(model.result)
        model.language = .english
        model.start(segment: segment, configuration: ModelConfiguration(), vocabulary: [])
        try await waitForResult(model)
        XCTAssertEqual(model.result?.segmentID, segment.id)
        XCTAssertTrue(model.editableText.contains("Demo question"))
    }
}

private struct ScriptedTranscription: TranscriptionService {
    var failAfterFinal = false
    var wrongSource = false
    var text = "Финальный текст"
    func transcribe(_ segment: AudioSegment, language: TranscriptionLanguage,
                    vocabulary: [String]) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            let output = AudioSegment(id: segment.id,
                                      source: wrongSource ? (segment.source == .system ? .microphone : .system) : segment.source,
                                      startedAt: segment.startedAt, samples: segment.samples, reason: "Тест")
            continuation.yield(.final(TranscriptResult(segment: output, text: text, isDemo: true)))
            continuation.yield(.partial("Запоздалый текст"))
            continuation.yield(.final(TranscriptResult(segment: output, text: "Дубликат", isDemo: true)))
            if failAfterFinal { continuation.finish(throwing: ProviderError.transport) }
            else { continuation.finish() }
        }
    }
}
