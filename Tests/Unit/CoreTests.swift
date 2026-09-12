import XCTest
import CopilotCore

final class CoreTests: XCTestCase {
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
        let reopened = PreferencesStore(defaults: defaults)
        XCTAssertEqual(reopened.theme, .dark)
        XCTAssertEqual(reopened.profile, .hr)
        XCTAssertTrue(reopened.onboardingCompleted)
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
        let store = PreferencesStore(defaults: defaults)
        XCTAssertEqual(store.theme, .system)
        XCTAssertEqual(store.profile, .liveCoding)
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
