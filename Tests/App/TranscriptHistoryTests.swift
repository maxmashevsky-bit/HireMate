import XCTest
import CopilotCore

final class TranscriptHistoryTests: XCTestCase {
    @MainActor
    func testSavedMeetingRestoresTimelineWithoutRestoringConsentOrLiveState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBMeetingRepository(directory: root)
        let meeting = Meeting(profileID: .technical, title: "История", isEphemeral: false)
        try await repository.createMeeting(meeting, initialChat: Subchat(meetingID: meeting.id, title: "Основной"))
        let first = model(repository)
        first.activateMeeting(meeting.id, profile: .technical, persisted: true)
        try await idle(first)
        first.start(segment: segment(0), configuration: ModelConfiguration(), vocabulary: [])
        try await idle(first)
        first.remoteConsent = true; first.includeRecentContext = true
        XCTAssertTrue(first.enableLive(configuration: ModelConfiguration(), vocabulary: []))
        await first.waitForPendingHistoryWrites()
        let expected = first.transcriptEntries
        first.disableLive()

        let restored = model(GRDBMeetingRepository(directory: root))
        restored.activateMeeting(meeting.id, profile: .technical, persisted: true)
        try await idle(restored)
        XCTAssertEqual(restored.transcriptEntries, expected)
        XCTAssertEqual(try restored.timelineForExport(meetingID: meeting.id).entries, expected)
        XCTAssertThrowsError(try restored.timelineForExport(meetingID: UUID()))
        XCTAssertFalse(restored.remoteConsent)
        XCTAssertFalse(restored.includeRecentContext)
        XCTAssertFalse(restored.isLiveEnabled)
        XCTAssertNil(restored.result)
        XCTAssertNil(restored.suggestedQuestion)
        XCTAssertTrue(restored.contextForRequest().isEmpty)
        restored.includeRecentContext = true
        XCTAssertTrue(restored.contextForRequest().contains("Как работает Go?"))
        restored.clearTranscript()
        await restored.waitForPendingHistoryWrites()
        let afterClear = model(repository)
        afterClear.activateMeeting(meeting.id, profile: .technical, persisted: true)
        try await idle(afterClear)
        XCTAssertTrue(afterClear.transcriptEntries.isEmpty)
        XCTAssertEqual(afterClear.compactedTranscriptCount, 0)
    }

    @MainActor
    func testLateHistoryLoadCannotReplaceAnotherMeetingsEntries() async throws {
        let repository = ControlledTranscriptStore()
        let old = UUID(), next = UUID()
        var oldTimeline = TranscriptTimeline(), nextTimeline = TranscriptTimeline()
        oldTimeline.append(TranscriptResult(segment: segment(0), text: "Старая встреча", isDemo: false))
        nextTimeline.append(TranscriptResult(segment: segment(1), text: "Новая встреча", isDemo: false))
        await repository.seed(oldTimeline, meeting: old)
        await repository.seed(nextTimeline, meeting: next)
        await repository.pauseNextLoad()
        let transcription = model(repository)
        transcription.activateMeeting(old, profile: .technical, persisted: true)
        try await eventually { await repository.isLoadPaused }
        transcription.activateMeeting(next, profile: .hr, persisted: true)
        try await idle(transcription)
        await repository.releaseLoad()
        await Task.yield()
        XCTAssertEqual(transcription.meetingID, next)
        XCTAssertEqual(transcription.transcriptEntries.map(\.text), ["Новая встреча"])
        XCTAssertFalse(transcription.isLoadingHistory)
    }

    @MainActor
    func testFailedLoadBlocksOverwriteUntilExplicitRetry() async throws {
        let repository = ControlledTranscriptStore()
        let id = UUID()
        var timeline = TranscriptTimeline()
        timeline.append(TranscriptResult(segment: segment(0), text: "Сохранённый текст", isDemo: false))
        await repository.seed(timeline, meeting: id)
        await repository.failLoads(true)
        let transcription = model(repository)
        transcription.activateMeeting(id, profile: .technical, persisted: true)
        try await idle(transcription)
        XCTAssertTrue(transcription.historyLoadFailed)
        XCTAssertThrowsError(try transcription.timelineForExport(meetingID: id))
        transcription.start(segment: segment(1), configuration: ModelConfiguration(), vocabulary: [])
        XCTAssertFalse(transcription.isRunning)
        XCTAssertFalse(transcription.enableLive(configuration: ModelConfiguration(), vocabulary: []))
        transcription.clearTranscript()
        let writes = await repository.writeCount
        XCTAssertEqual(writes, 0)
        await repository.failLoads(false)
        transcription.retryHistoryLoad()
        try await idle(transcription)
        XCTAssertFalse(transcription.historyLoadFailed)
        XCTAssertEqual(transcription.transcriptEntries.map(\.text), ["Сохранённый текст"])
    }

    @MainActor
    func testFailedSaveKeepsLatestSnapshotAcrossNavigationAndRetries() async throws {
        let repository = ControlledTranscriptStore()
        await repository.failSaves(true)
        let id = UUID()
        let transcription = model(repository)
        transcription.activateMeeting(id, profile: .technical, persisted: true)
        try await idle(transcription)
        for index in 0..<3 {
            transcription.start(segment: segment(index), configuration: ModelConfiguration(), vocabulary: [])
            try await idle(transcription)
            await transcription.waitForPendingHistoryWrites()
        }
        XCTAssertEqual(transcription.unsavedTranscriptCount, 1)
        let entries = transcription.transcriptEntries
        transcription.activateMeeting(UUID())
        transcription.activateMeeting(id, profile: .technical, persisted: true)
        try await idle(transcription)
        XCTAssertEqual(transcription.transcriptEntries, entries)
        await repository.failSaves(false)
        transcription.retryHistorySaves()
        await transcription.waitForPendingHistoryWrites()
        XCTAssertEqual(transcription.unsavedTranscriptCount, 0)
        let saved = try await repository.transcriptTimeline(meetingID: id, profile: .technical)
        XCTAssertEqual(saved.entries, entries)
    }

    @MainActor
    func testWritesAreCoalescedAndAwaitedWhileMemoryMeetingsStayTransient() async throws {
        let repository = ControlledTranscriptStore()
        let transcription = model(repository)
        transcription.activateMeeting(UUID())
        transcription.start(segment: segment(0), configuration: ModelConfiguration(), vocabulary: [])
        try await idle(transcription)
        await transcription.waitForPendingHistoryWrites()
        let ephemeralWrites = await repository.writeCount
        XCTAssertEqual(ephemeralWrites, 0)

        let savedID = UUID()
        transcription.activateMeeting(savedID, profile: .technical, persisted: true)
        try await idle(transcription)
        await repository.pauseNextSave()
        transcription.start(segment: segment(1), configuration: ModelConfiguration(), vocabulary: [])
        try await idle(transcription)
        try await eventually { await repository.isSavePaused }
        for index in 2..<5 {
            transcription.start(segment: segment(index), configuration: ModelConfiguration(), vocabulary: [])
            try await idle(transcription)
        }
        XCTAssertTrue(transcription.isSavingHistory)
        await repository.releaseSave()
        await transcription.waitForPendingHistoryWrites()
        let writes = await repository.writeCount
        let saved = try await repository.transcriptTimeline(meetingID: savedID, profile: .technical)
        XCTAssertEqual(writes, 2)
        XCTAssertEqual(saved.entries.count, 4)
        XCTAssertFalse(transcription.isSavingHistory)
    }

    @MainActor
    func testLateWriteDoesNotRecreateDeletedMeeting() async throws {
        let repository = ControlledTranscriptStore()
        let transcription = model(repository)
        let id = UUID()
        transcription.activateMeeting(id, profile: .technical, persisted: true)
        try await idle(transcription)
        await repository.pauseNextSave()
        transcription.start(segment: segment(1), configuration: ModelConfiguration(), vocabulary: [])
        try await idle(transcription)
        try await eventually { await repository.isSavePaused }
        await repository.delete(id)
        await repository.releaseSave()
        await transcription.waitForPendingHistoryWrites()
        XCTAssertEqual(transcription.unsavedTranscriptCount, 0)
        XCTAssertTrue(transcription.historyStatus.contains("больше не доступна"))
        let exists = await repository.contains(id)
        XCTAssertFalse(exists)
    }

    @MainActor
    private func model(_ repository: any TranscriptRepository) -> TranscriptionModel {
        TranscriptionModel(secrets: HistoryNoSecrets(), network: NetworkClient(),
                           serviceFactory: { _ in HistoryTranscription() }, transcriptRepository: repository)
    }
    private func segment(_ index: Int) -> AudioSegment {
        AudioSegment(source: .system, startedAt: Double(index), samples: [0.1], reason: "Тест")
    }
    @MainActor
    private func idle(_ model: TranscriptionModel) async throws {
        try await eventually { @MainActor in !model.isBusy }
    }
    @MainActor
    private func eventually(_ predicate: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else { throw LocalStoreError.unavailable }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
private struct HistoryNoSecrets: SecureSecretStore {
    func save(_ secret: String) throws { XCTFail("История не сохраняет ключ") }
    func read() throws -> String? { XCTFail("Демо не читает ключ"); return nil }
    func delete() throws { XCTFail("История не удаляет ключ") }
}

private struct HistoryTranscription: TranscriptionService {
    func transcribe(_ segment: AudioSegment, language: TranscriptionLanguage,
                    vocabulary: [String]) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.final(TranscriptResult(segment: segment, text: "Как работает Go?", isDemo: true)))
            continuation.finish()
        }
    }
}

private actor ControlledTranscriptStore: TranscriptRepository {
    private var snapshots: [UUID: TranscriptTimeline] = [:]
    private var deleted = Set<UUID>()
    private var loadFails = false, saveFails = false, holdLoad = false, holdSave = false
    private var loadGate: CheckedContinuation<Void, Never>?
    private var saveGate: CheckedContinuation<Void, Never>?
    private(set) var writeCount = 0
    var isLoadPaused: Bool { loadGate != nil }
    var isSavePaused: Bool { saveGate != nil }
    func seed(_ timeline: TranscriptTimeline, meeting: UUID) { snapshots[meeting] = timeline }
    func contains(_ id: UUID) -> Bool { snapshots[id] != nil }
    func delete(_ id: UUID) { deleted.insert(id); snapshots.removeValue(forKey: id) }
    func failLoads(_ value: Bool) { loadFails = value }
    func failSaves(_ value: Bool) { saveFails = value }
    func pauseNextLoad() { holdLoad = true }
    func pauseNextSave() { holdSave = true }
    func releaseLoad() { loadGate?.resume(); loadGate = nil }
    func releaseSave() { saveGate?.resume(); saveGate = nil }
    func transcriptTimeline(meetingID: UUID, profile: ProfileID) async throws -> TranscriptTimeline {
        let snapshot = snapshots[meetingID] ?? TranscriptTimeline()
        if holdLoad { holdLoad = false; await withCheckedContinuation { loadGate = $0 } }
        if loadFails { throw LocalStoreError.unavailable }
        if deleted.contains(meetingID) { throw LocalStoreError.missingRecord }
        return snapshot
    }
    func saveTranscriptTimeline(_ timeline: TranscriptTimeline, meetingID: UUID, profile: ProfileID) async throws {
        writeCount += 1
        if holdSave { holdSave = false; await withCheckedContinuation { saveGate = $0 } }
        if deleted.contains(meetingID) { throw LocalStoreError.missingRecord }
        if saveFails { throw LocalStoreError.unavailable }
        snapshots[meetingID] = timeline
    }
}
