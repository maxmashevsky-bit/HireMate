import XCTest
import CopilotCore

@MainActor
private final class ControlledCapture: AudioCaptureService {
    var holdStart = false
    var holdStop = false
    var starts = 0
    var startedMode: AudioInputMode?
    var startGate: CheckedContinuation<Void, Never>?
    var stopGate: CheckedContinuation<Void, Never>?
    var frames: AsyncThrowingStream<AudioFrame, Error>.Continuation?

    func start(mode: AudioInputMode) async throws -> AsyncThrowingStream<AudioFrame, Error> {
        starts += 1
        startedMode = mode
        let pair = AsyncThrowingStream<AudioFrame, Error>.makeStream()
        frames = pair.continuation
        if holdStart { await withCheckedContinuation { startGate = $0 } }
        return pair.stream
    }
    func stop() async {
        if holdStop { await withCheckedContinuation { stopGate = $0 } }
        frames?.finish()
    }
    func releaseStart() { holdStart = false; startGate?.resume(); startGate = nil }
    func releaseStop() { holdStop = false; stopGate?.resume(); stopGate = nil }
}

@MainActor
private struct DemoSecrets: SecureSecretStore {
    func save(_ secret: String) throws { XCTFail("Локальный демо-сценарий не сохраняет ключ") }
    func read() throws -> String? { XCTFail("Локальный демо-сценарий не читает ключ"); return nil }
    func delete() throws { XCTFail("Локальный демо-сценарий не удаляет ключ") }
}

final class AudioSessionTests: XCTestCase {
    @MainActor
    func testAudioSettingsSurviveRecreationAndCaptureRequiresFreshConsent() async throws {
        let suite = "AudioSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AudioSessionModel(capture: ControlledCapture(), preferences: PreferencesStore(defaults: defaults))
        first.inputMode = .combined
        first.questionMode = .oneShot
        var configuration = AudioPipelineConfiguration()
        configuration.preRoll = 9; configuration.oneShot = 35; configuration.chunkSeconds = 12
        configuration.micSilence = 2; configuration.systemSilence = 3
        configuration.threshold = 0.08; configuration.minSpeech = 0.4
        configuration.speechCheck = false; configuration.clearAfterOneShot = false
        first.configuration = configuration
        first.consent = true
        let capture = ControlledCapture()
        let reopened = AudioSessionModel(capture: capture, preferences: PreferencesStore(defaults: defaults))
        XCTAssertEqual(reopened.inputMode, .combined)
        XCTAssertEqual(reopened.questionMode, .oneShot)
        XCTAssertEqual(reopened.configuration, configuration)
        XCTAssertFalse(reopened.consent)
        XCTAssertFalse(reopened.isRunning)
        reopened.start()
        XCTAssertEqual(capture.starts, 0)
        reopened.consent = true
        reopened.start()
        try await eventually { reopened.isRunning }
        XCTAssertEqual(capture.startedMode, .combined)
        await reopened.shutdown()
        await first.shutdown()
    }

    @MainActor
    func testInvalidAudioSettingsFallBackAndStayFinite() throws {
        let suite = "AudioSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown", forKey: "audio.inputMode")
        defaults.set("unknown", forKey: "audio.questionMode")
        defaults.set(Data("invalid json".utf8), forKey: "audio.configuration")
        let preferences = PreferencesStore(defaults: defaults)
        XCTAssertEqual(preferences.audioInputMode, .microphone)
        XCTAssertEqual(preferences.audioQuestionMode, .manual)
        XCTAssertEqual(preferences.audioConfiguration, AudioPipelineConfiguration())
        let model = AudioSessionModel(capture: ControlledCapture(), preferences: preferences)
        var invalid = AudioPipelineConfiguration()
        invalid.preRoll = .nan; invalid.oneShot = .infinity; invalid.chunkSeconds = -.infinity
        invalid.micSilence = -5; invalid.systemSilence = 50
        invalid.threshold = .nan; invalid.minSpeech = .infinity
        model.configuration = invalid
        var expected = AudioPipelineConfiguration()
        expected.micSilence = 0.5; expected.systemSilence = 5
        XCTAssertEqual(model.configuration, expected)
        XCTAssertEqual(PreferencesStore(defaults: defaults).audioConfiguration, expected)
        var oversized = AudioPipelineConfiguration()
        oversized.preRoll = 99; oversized.oneShot = -1; oversized.chunkSeconds = 99
        oversized.threshold = -1; oversized.minSpeech = -1
        defaults.set(try JSONEncoder().encode(oversized), forKey: "audio.configuration")
        XCTAssertEqual(PreferencesStore(defaults: defaults).audioConfiguration, oversized.bounded())
    }

    @MainActor
    func testLocalDemoConnectsAudioTranscriptionQuestionAndAnswer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = ControlledCapture()
        let repository = GRDBMeetingRepository(directory: directory)
        let secrets = DemoSecrets()
        let network = NetworkClient()
        let audio = AudioSessionModel(capture: capture)
        let transcription = TranscriptionModel(secrets: secrets, network: network)
        let conversation = ConversationModel(profileID: .technical, repository: repository,
                                              secrets: secrets, network: network, noteSearch: repository)
        audio.onSegment = { transcription.enqueueLive($0) }
        audio.inputMode = .system
        audio.questionMode = .manual
        audio.configuration.speechCheck = false
        audio.consent = true
        XCTAssertTrue(transcription.enableLive(configuration: ModelConfiguration(),
                                               vocabulary: conversation.profile.technologies))

        audio.start()
        try await eventually { audio.isRunning }
        await audio.toggleManualQuestion()
        capture.frames?.yield(AudioFrame(timestamp: 1, source: .system, sampleRate: 16_000,
                                         samples: Array(repeating: 0.2, count: 8_000)))
        try await eventually { (audio.buffered[.system] ?? 0) > 0 }
        await audio.toggleManualQuestion()
        try await eventually { transcription.suggestedQuestion != nil && !transcription.isBusy }

        conversation.draft = try XCTUnwrap(transcription.takeSuggestedQuestion())
        conversation.send(configuration: ModelConfiguration())
        try await eventually(timeout: .seconds(4)) { !conversation.isGenerating && !conversation.answer.isEmpty }
        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.messages.last?.state, .complete)
        XCTAssertEqual(conversation.messages.last?.isDemo, true)
        XCTAssertFalse(transcription.transcriptEntries.isEmpty)
        await audio.shutdown()
    }

    @MainActor
    func testDeliveryGapStopsCaptureAndClearsBuffer() async throws {
        let capture = ControlledCapture()
        let model = AudioSessionModel(capture: capture)
        model.consent = true
        model.start()
        try await eventually { model.isRunning }
        capture.frames?.yield(AudioFrame(timestamp: 1, source: .microphone, sampleRate: 16_000,
                                        samples: Array(repeating: 0.2, count: 1_600)))
        try await eventually { !model.buffered.isEmpty }
        capture.frames?.yield(AudioFrame(timestamp: 2, source: .microphone, sampleRate: 16_000,
                                        samples: Array(repeating: 0.2, count: 1_600)))
        try await eventually { !model.isRunning && !model.isStopping }
        XCTAssertTrue(model.buffered.isEmpty)
        XCTAssertTrue(model.segments.isEmpty)
        XCTAssertEqual(capture.starts, 1)
        await model.shutdown()
    }
    @MainActor
    private func eventually(timeout: Duration = .seconds(3), _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !predicate() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Состояние аудиосессии не изменилось вовремя")
                throw AudioPipelineError.interrupted
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor
    func testRestartWaitsForStopAndRejectsOldFrames() async throws {
        let capture = ControlledCapture()
        let model = AudioSessionModel(capture: capture)
        model.consent = true
        model.start()
        try await eventually { model.isRunning }
        let oldFrames = capture.frames
        capture.holdStop = true
        let stop = Task { await model.stop() }
        try await eventually { capture.stopGate != nil }
        model.start()
        XCTAssertEqual(capture.starts, 1)
        XCTAssertTrue(model.isStopping)
        capture.releaseStop()
        await stop.value
        model.start()
        try await eventually { model.isRunning }
        XCTAssertEqual(capture.starts, 2)
        oldFrames?.yield(AudioFrame(timestamp: 1, source: .microphone, sampleRate: 16_000, samples: [0.5]))
        XCTAssertTrue(model.levels.isEmpty)
        await model.shutdown()
    }

    @MainActor
    func testStopDuringOpeningWaitsForSystemCallback() async throws {
        let capture = ControlledCapture()
        capture.holdStart = true
        let model = AudioSessionModel(capture: capture)
        model.consent = true
        model.start()
        try await eventually { capture.startGate != nil }
        let stop = Task { await model.stop() }
        try await eventually { model.isStopping }
        model.start()
        XCTAssertEqual(capture.starts, 1)
        capture.releaseStart()
        await stop.value
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.isStarting)
        model.start()
        try await eventually { model.isRunning }
        XCTAssertEqual(capture.starts, 2)
        await model.shutdown()
    }

    @MainActor
    func testBothMetersUpdateAtSameTimestampAndClear() async throws {
        let capture = ControlledCapture()
        let model = AudioSessionModel(capture: capture)
        model.consent = true
        model.inputMode = .combined
        model.start()
        try await eventually { model.isRunning }
        for source in AudioSource.allCases {
            capture.frames?.yield(AudioFrame(timestamp: 1, source: source, sampleRate: 16_000,
                                            samples: Array(repeating: 0.25, count: 1_600)))
        }
        try await eventually { model.levels.count == 2 }
        XCTAssertGreaterThan(model.levels[.microphone] ?? 0, 0)
        XCTAssertGreaterThan(model.levels[.system] ?? 0, 0)
        await model.clear()
        XCTAssertTrue(model.levels.isEmpty)
        XCTAssertTrue(model.buffered.isEmpty)
        XCTAssertTrue(model.states.isEmpty)
        await model.shutdown()
    }
}
