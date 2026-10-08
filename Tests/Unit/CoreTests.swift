import XCTest
import CopilotCore

final class CoreTests: XCTestCase {
    func testSavedTranscriptTimelineIsMeetingScopedRestoresAndCascadesWithDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = GRDBMeetingRepository(directory: directory)
        let meeting = Meeting(profileID: .technical, title: "Расшифровки", isEphemeral: false)
        let other = Meeting(profileID: .technical, title: "Другая встреча", isEphemeral: false)
        for parent in [meeting, other] { try await repository.createMeeting(parent, initialChat: Subchat(meetingID: parent.id, title: "Основной")) }
        var timeline = TranscriptTimeline()
        let segment = AudioSegment(source: .system, startedAt: 1, samples: [0.1], reason: "Тест")
        timeline.append(TranscriptResult(segment: segment, text: "Вопрос собеседника", isDemo: false))
        try await repository.saveTranscriptTimeline(timeline, meetingID: meeting.id, profile: .technical)
        let reopened = GRDBMeetingRepository(directory: directory)
        let loaded = try await reopened.transcriptTimeline(meetingID: meeting.id, profile: .technical)
        XCTAssertEqual(loaded, timeline)
        let isolated = try await reopened.transcriptTimeline(meetingID: other.id, profile: .technical)
        XCTAssertTrue(isolated.entries.isEmpty)
        do {
            try await repository.saveTranscriptTimeline(timeline, meetingID: meeting.id, profile: .hr)
            XCTFail("Другой профиль не может писать историю")
        } catch LocalStoreError.missingRecord { }
        do {
            _ = try await repository.transcriptTimeline(meetingID: meeting.id, profile: .hr)
            XCTFail("Другой профиль не может читать историю")
        } catch LocalStoreError.missingRecord { }
        timeline.clear()
        try await repository.saveTranscriptTimeline(timeline, meetingID: meeting.id, profile: .technical)
        let cleared = try await reopened.transcriptTimeline(meetingID: meeting.id, profile: .technical)
        XCTAssertTrue(cleared.entries.isEmpty)
        try await repository.deleteMeeting(id: meeting.id)
        do {
            _ = try await reopened.transcriptTimeline(meetingID: meeting.id, profile: .technical)
            XCTFail("История удалённой встречи не доступна")
        } catch LocalStoreError.missingRecord { }
    }

    func testMeetingOverviewsCountWithoutJoinInflationAndRenameIsScoped() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = GRDBMeetingRepository(directory: directory)
        let meeting = Meeting(profileID: .technical, title: "Исходное имя", isEphemeral: false)
        let first = Subchat(meetingID: meeting.id, title: "Первый")
        let second = Subchat(meetingID: meeting.id, title: "Второй")
        try await repository.createMeeting(meeting, initialChat: first)
        try await repository.saveSubchat(second)
        let future = Date().addingTimeInterval(1_000)
        for chat in [first, first, second] {
            try await repository.saveMessage(ChatMessage(subchatID: chat.id, role: .user, content: "Текст", createdAt: future), meetingID: meeting.id)
        }
        let overview = try await repository.meetingOverviews(profile: .technical)
        XCTAssertEqual(overview.first?.subchatCount, 2)
        XCTAssertEqual(overview.first?.messageCount, 3)
        XCTAssertEqual(overview.first?.meeting.updatedAt, future)
        do {
            _ = try await repository.renameMeeting(id: meeting.id, profile: .hr, title: "Чужое имя")
            XCTFail("Переименование другого профиля должно отклоняться")
        } catch LocalStoreError.missingRecord { }
        for invalid in ["", " \n", String(repeating: "x", count: 121)] {
            do {
                _ = try await repository.renameMeeting(id: meeting.id, profile: .technical, title: invalid)
                XCTFail("Недопустимое название")
            } catch LocalStoreError.invalidData { }
        }
        let renamed = try await repository.renameMeeting(id: meeting.id, profile: .technical, title: "  Новое имя  ")
        XCTAssertEqual(renamed.title, "Новое имя")
        XCTAssertEqual(renamed.updatedAt, future)
        let reopened = GRDBMeetingRepository(directory: directory)
        let after = try await reopened.meetingOverviews(profile: .technical)
        XCTAssertEqual(after.first?.meeting.title, "Новое имя")
        XCTAssertEqual(after.first?.messageCount, 3)
    }

    func testMessageWindowKeepsNewestMessagesAndBoundsCharacters() {
        let chat = UUID()
        let history = (0..<8).map { ChatMessage(subchatID: chat, role: .user, content: String(repeating: "x", count: 300) + "-\($0)") }
        let result = BoundedMessageWindow(maximumMessages: 4, maximumCharacters: 1_024).apply(to: history)
        XCTAssertEqual(result.messages.count, 3)
        XCTAssertEqual(result.omittedCount, 5)
        XCTAssertEqual(result.messages.map { String($0.content.suffix(2)) }, ["-5", "-6", "-7"])
        XCTAssertLessThanOrEqual(result.messages.reduce(0) { $0 + $1.content.count }, 1_024)

        let oversized = ChatMessage(subchatID: chat, role: .assistant, content: String(repeating: "я", count: 2_000))
        let clipped = BoundedMessageWindow(maximumMessages: 4, maximumCharacters: 1_024).apply(to: [oversized])
        XCTAssertEqual(clipped.clippedCount, 1)
        XCTAssertLessThanOrEqual(clipped.messages[0].content.count, 1_024)
    }
    @MainActor
    func testLocalDatabaseBenchmarkUsesNearestRankP95AndMeetsPersonalBudget() async throws {
        let summary = LatencySummary(samplesMilliseconds: [10, 1, 3, 2, 100, 4, 5, 6, 7, 8,
                                                              9, 11, 12, 13, 14, 15, 16, 17, 18, 19])
        XCTAssertEqual(summary.sampleCount, 20)
        XCTAssertEqual(summary.p95Milliseconds, 19)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hiremate-db-benchmark-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = GRDBMeetingRepository(directory: directory)
        let result = try await LocalDatabaseBenchmark(repository: repository).measureMeetings(profile: .technical)
        XCTAssertEqual(result.sampleCount, 20)
        XCTAssertLessThan(result.p95Milliseconds, 100)
        XCTAssertLessThanOrEqual(result.minimumMilliseconds, result.p95Milliseconds)
        XCTAssertLessThanOrEqual(result.p95Milliseconds, result.maximumMilliseconds)
    }
    @MainActor
    func testDatabaseMeetingIsolationAndCascade() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hiremate-db-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = GRDBMeetingRepository(directory: directory)
        let profiles = try await repository.profiles()
        XCTAssertEqual(Set(profiles.map(\.id)), Set(ProfileID.allCases))
        let first = Meeting(profileID: .technical, title: "Первая", isEphemeral: false)
        let second = Meeting(profileID: .hr, title: "Вторая", isEphemeral: false)
        let chat = Subchat(meetingID: first.id, title: "Основной")
        let other = Subchat(meetingID: second.id, title: "Другой")
        try await repository.createMeeting(first, initialChat: chat)
        try await repository.createMeeting(second, initialChat: other)
        let message = ChatMessage(subchatID: chat.id, role: .user, content: "Горутины")
        try await repository.saveMessage(message, meetingID: first.id)
        do {
            try await repository.saveMessage(message, meetingID: second.id)
            XCTFail("Запись с чужим meetingID должна отклоняться")
        } catch LocalStoreError.missingRecord { }
        let reopened = GRDBMeetingRepository(directory: directory)
        let loaded = try await reopened.messages(subchatID: chat.id, meetingID: first.id)
        let isolated = try await reopened.messages(subchatID: chat.id, meetingID: second.id)
        XCTAssertEqual(loaded, [message]); XCTAssertTrue(isolated.isEmpty)
        try await repository.deleteMeeting(id: first.id)
        let deleted = try await reopened.messages(subchatID: chat.id, meetingID: first.id)
        let remaining = try await reopened.meetings(profile: .hr)
        XCTAssertTrue(deleted.isEmpty); XCTAssertEqual(remaining.map(\.id), [second.id])
    }

    func testVacancyTrackerPersistsMovesArchiveAndCustomStageOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hiremate-tracker-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = GRDBMeetingRepository(directory: directory)
        var stages = try await repository.vacancyStages()
        XCTAssertEqual(stages.map(\.name), VacancyStage.standard.map(\.name))
        let custom = VacancyStage(name: "Тестовое задание", position: 1)
        stages.insert(custom, at: 1)
        try await repository.saveVacancyStages(stages)

        let vacancy = Vacancy(stageID: stages[0].id, company: "Acme", title: "Go Developer",
                              salary: "200–250", grade: "Junior", workFormat: "Удалённо")
        try await repository.saveVacancy(vacancy)
        let movedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try await repository.moveVacancy(id: vacancy.id, to: custom.id, at: movedAt)
        var loaded = try await repository.vacancies(includeArchived: false)
        XCTAssertEqual(loaded.first?.stageID, custom.id)
        let transitions = try await repository.vacancyTransitions()
        XCTAssertEqual(transitions.first?.happenedAt, movedAt)

        try await repository.setVacancyArchived(id: vacancy.id, archived: true, at: movedAt.addingTimeInterval(10))
        loaded = try await repository.vacancies(includeArchived: false)
        XCTAssertTrue(loaded.isEmpty)
        let archived = try await repository.vacancies(includeArchived: true).filter(\.isArchived)
        XCTAssertEqual(archived.map(\.id), [vacancy.id])

        let reopened = GRDBMeetingRepository(directory: directory)
        let reopenedStages = try await reopened.vacancyStages()
        XCTAssertEqual(reopenedStages.map(\.id), stages.enumerated().map { index, stage in
            var value = stage; value.position = index; return value.id
        })
        let reopenedTransitions = try await reopened.vacancyTransitions()
        XCTAssertEqual(reopenedTransitions.count, 1)
    }

    @MainActor
    func testDatabaseNoteIndexReplacementAndConsent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hiremate-fts-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = GRDBMeetingRepository(directory: directory)
        var note = Note(profileID: .technical, title: "Конкурентность", markdown: "Горутины используют каналы.")
        try await repository.saveNote(note)
        let privateResults = try await repository.retrieve(query: "Горутины", profile: .technical, tags: [], limit: 4)
        XCTAssertTrue(privateResults.isEmpty)
        note.allowAI = true; note.tags = ["Go"]
        try await repository.saveNote(note)
        let allowed = try await repository.retrieve(query: "Горутины", profile: .technical, tags: ["Go"], limit: 4)
        let wrongProfile = try await repository.retrieve(query: "Горутины", profile: .hr, tags: [], limit: 4)
        XCTAssertEqual(allowed.count, 1); XCTAssertTrue(wrongProfile.isEmpty)
        note.markdown = "Транзакции обеспечивают атомарность."
        try await repository.saveNote(note)
        let stale = try await repository.retrieve(query: "Горутины", profile: .technical, tags: [], limit: 4)
        let fresh = try await repository.notes(profile: .technical, query: "Транзакции", includeArchived: false)
        XCTAssertTrue(stale.isEmpty); XCTAssertEqual(fresh.map(\.id), [note.id])
        try await repository.deleteNote(id: note.id, profile: .technical)
        let removed = try await repository.retrieve(query: "Транзакции", profile: .technical, tags: [], limit: 4)
        XCTAssertTrue(removed.isEmpty)
    }

    @MainActor
    func testPreferencesRoundTripAndAllowlist() throws {
        let name = "dev.maxmashevsky.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PreferencesStore(defaults: defaults)
        XCTAssertEqual(store.theme, .system)
        XCTAssertEqual(store.profile, .liveCoding)
        XCTAssertFalse(store.onboardingCompleted)
        store.theme = .dark
        store.profile = .hr
        store.onboardingCompleted = true
        store.accent = AppAccent(rgb: 0x335577)
        store.messageFontSize = 18
        XCTAssertTrue(store.retainCancelledAnswer)
        store.retainCancelledAnswer = false
        XCTAssertFalse(store.cancelGenerationOnSend)
        store.cancelGenerationOnSend = true
        store.codeTheme = .monokai
        store.syntaxHighlighting = false
        XCTAssertEqual(store.messageOrder, .newestBottom)
        store.messageOrder = .newestTop
        XCTAssertFalse(store.collapseAnswers)
        XCTAssertFalse(store.collapseLatestAnswer)
        store.collapseAnswers = true
        store.collapseLatestAnswer = true
        XCTAssertFalse(store.collapseTranscripts)
        XCTAssertFalse(store.collapseLatestTranscript)
        store.collapseTranscripts = true
        store.collapseLatestTranscript = true
        store.audioInputMode = .combined
        store.audioQuestionMode = .oneShot
        store.audioConfiguration.preRoll = 9
        let reopened = PreferencesStore(defaults: defaults)
        XCTAssertEqual(reopened.theme, .dark)
        XCTAssertEqual(reopened.profile, .hr)
        XCTAssertTrue(reopened.onboardingCompleted)
        XCTAssertEqual(reopened.accent.hex, "#335577")
        XCTAssertEqual(reopened.messageFontSize, 18)
        XCTAssertFalse(reopened.retainCancelledAnswer)
        XCTAssertTrue(reopened.cancelGenerationOnSend)
        XCTAssertEqual(reopened.codeTheme, .monokai)
        XCTAssertFalse(reopened.syntaxHighlighting)
        XCTAssertEqual(reopened.messageOrder, .newestTop)
        XCTAssertTrue(reopened.collapseAnswers)
        XCTAssertTrue(reopened.collapseLatestAnswer)
        XCTAssertTrue(reopened.collapseTranscripts)
        XCTAssertTrue(reopened.collapseLatestTranscript)
        XCTAssertEqual(reopened.audioInputMode, .combined)
        XCTAssertEqual(reopened.audioQuestionMode, .oneShot)
        XCTAssertEqual(reopened.audioConfiguration.preRoll, 9)
        let keys = Set((defaults.persistentDomain(forName: name) ?? [:]).keys)
        XCTAssertEqual(keys, Set(PreferencesStore.allowedKeys))
    }
    @MainActor
    func testCorruptPreferencesFallBack() throws {
        let name = "dev.maxmashevsky.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("not-a-theme", forKey: "ui.theme")
        defaults.set("not-a-profile", forKey: "ui.profile")
        defaults.set("not-a-color", forKey: "ui.accent")
        defaults.set("not-a-boolean", forKey: "ui.retainCancelledAnswer")
        defaults.set("not-a-boolean", forKey: "ui.cancelGenerationOnSend")
        defaults.set("not-a-theme", forKey: "ui.codeTheme")
        defaults.set("not-a-boolean", forKey: "ui.syntaxHighlighting")
        defaults.set("not-an-order", forKey: "ui.messageOrder")
        defaults.set("not-a-boolean", forKey: "ui.collapseAnswers")
        defaults.set("not-a-boolean", forKey: "ui.collapseLatestAnswer")
        defaults.set("not-a-boolean", forKey: "ui.collapseTranscripts")
        defaults.set("not-a-boolean", forKey: "ui.collapseLatestTranscript")
        let store = PreferencesStore(defaults: defaults)
        XCTAssertEqual(store.theme, .system)
        XCTAssertEqual(store.profile, .liveCoding)
        XCTAssertEqual(store.accent, .defaultColor)
        XCTAssertTrue(store.retainCancelledAnswer)
        XCTAssertFalse(store.cancelGenerationOnSend)
        XCTAssertEqual(store.codeTheme, .githubDark)
        XCTAssertTrue(store.syntaxHighlighting)
        XCTAssertEqual(store.messageOrder, .newestBottom)
        XCTAssertFalse(store.collapseAnswers)
        XCTAssertFalse(store.collapseLatestAnswer)
        XCTAssertFalse(store.collapseTranscripts)
        XCTAssertFalse(store.collapseLatestTranscript)
    }
    func testAccentAcceptsRGBHexAndRejectsMalformedStoredValues() throws {
        let accent = try XCTUnwrap(AppAccent(hex: " #aB19fF \n"))
        XCTAssertEqual(accent.hex, "#AB19FF")
        XCTAssertEqual(accent.red, 171.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(accent.green, 25.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(accent.blue, 1)
        for invalid in ["", "#FFF", "#FF000080", "+23456", "GG0000", "#12 456"] {
            XCTAssertNil(AppAccent(hex: invalid), invalid)
        }
    }
    func testAccentForegroundRemainsReadableForDarkAndLightColors() {
        for rgb: UInt32 in [0xFFFFFF, 0x40F0A3, 0xFFFF00, 0x00A000] {
            XCTAssertTrue(AppAccent(rgb: rgb).prefersDarkText)
        }
        for rgb: UInt32 in [0x000000, 0x0000FF, 0x335577, 0x333333, 0x008000] {
            XCTAssertFalse(AppAccent(rgb: rgb).prefersDarkText)
        }
    }
    @MainActor
    func testMessageFontSizeClampsInvalidInputBeforeDisplayAndPersistence() throws {
        let name = "FontSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Double.infinity, forKey: "ui.messageFontSize")
        let store = PreferencesStore(defaults: defaults)
        XCTAssertEqual(store.messageFontSize, 13.5)
        store.messageFontSize = 100
        XCTAssertEqual(store.messageFontSize, 22)
        XCTAssertEqual(PreferencesStore(defaults: defaults).messageFontSize, 22)
        store.messageFontSize = -1
        XCTAssertEqual(store.messageFontSize, 11)
        store.messageFontSize = .nan
        XCTAssertEqual(store.messageFontSize, 13.5)
        XCTAssertEqual(PreferencesStore(defaults: defaults).messageFontSize, 13.5)
    }
    func testUnknownPermissionFailsClosed() {
        for status in [PermissionState.denied, .restricted, .unconfirmed, .notRequested] { XCTAssertFalse(status.canCapture) }
        XCTAssertTrue(PermissionState.granted.canCapture)
    }
    func testInputBoundaryAndUnicode() {
        XCTAssertFalse(InputValidation.canSend(" \n\t\u{00A0}"))
        XCTAssertTrue(InputValidation.canSend(String(repeating: "я", count: 4_000)))
        XCTAssertFalse(InputValidation.canSend(String(repeating: "я", count: 4_001)))
    }
    func testFakeStreamsDistinctProfiles() async throws {
        var responses: [String] = []
        for profile in ProfileID.allCases {
            var output = ""
            var count = 0
            for try await chunk in FakeLLMProvider(delayNanoseconds: 0).stream(DemoRequest(profile: profile, question: "Контрольный вопрос")) {
                output += chunk
                count += 1
            }
            XCTAssertGreaterThan(count, 5)
            XCTAssertTrue(output.contains("AI и сеть не используются"))
            responses.append(output)
        }
        XCTAssertEqual(Set(responses).count, 3)
        XCTAssertTrue(responses[0].contains("func sum"))
        XCTAssertFalse(responses[2].contains("func sum"))
        XCTAssertTrue(responses[2].contains("подтверждённые факты"))
    }
    func testFakeRejectsEmptyInput() async {
        do {
            for try await _ in FakeLLMProvider(delayNanoseconds: 0).stream(DemoRequest(profile: .hr, question: "")) {}
            XCTFail("Ожидалась invalidInput")
        } catch DemoError.invalidInput {
            // Ожидаемый исход.
        } catch { XCTFail("Неверный тип ошибки") }
    }
}
