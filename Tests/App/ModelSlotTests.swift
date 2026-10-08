import XCTest
import CopilotCore

final class ModelSlotTests: XCTestCase {
    @MainActor
    func testFiveSlotsCyclePersistAndPreserveProviderAndTranscriptionConfiguration() throws {
        let suite = "ModelSlots.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ProviderSettingsModel(defaults: defaults)
        settings.configuration.mode = .remote
        settings.configuration.baseURL = "https://api.example.test/v1/"
        settings.configuration.transcriptionModel = "speech-test"
        settings.configuration.textModel = "initial"
        settings.configuration.timeoutSeconds = 35
        for number in 1...5 {
            XCTAssertTrue(settings.saveModelSlot(number: number, name: "Слот \(number)", model: "model-\(number)", supportsVision: number == 2,
                                                 maxContextTokens: number * 4_096, reservedOutputTokens: 512))
        }
        var configurationChanges = 0
        settings.onConfigurationChange = { configurationChanges += 1 }
        XCTAssertTrue(settings.activateModelSlot(2))
        XCTAssertEqual(configurationChanges, 1)
        XCTAssertEqual(settings.configuration.textModel, "model-2")
        XCTAssertTrue(settings.configuration.visionEnabled)
        XCTAssertEqual(settings.configuration.maxContextTokens, 8_192)
        XCTAssertEqual(settings.configuration.transcriptionModel, "speech-test")
        XCTAssertEqual(settings.configuration.timeoutSeconds, 35)
        XCTAssertEqual(settings.configuration.baseURL, "https://api.example.test/v1/")
        XCTAssertEqual(settings.configuration.secretReference, "ai.primary")
        let reopened = ProviderSettingsModel(defaults: defaults)
        XCTAssertEqual(reopened.modelSlots, settings.modelSlots)
        XCTAssertEqual(reopened.configuration, settings.configuration)
        XCTAssertEqual(reopened.activeSlotNumber, 2)
        for number in [3, 4, 5, 1, 2] {
            XCTAssertTrue(reopened.cycleModelSlot())
            XCTAssertEqual(reopened.activeSlotNumber, number)
            XCTAssertEqual(reopened.configuration.textModel, "model-\(number)")
        }
        reopened.removeModelSlot(2)
        XCTAssertNil(reopened.activeSlotNumber)
        XCTAssertEqual(reopened.configuration.textModel, "model-2")
        XCTAssertNil(ProviderSettingsModel(defaults: defaults).modelSlots[2])
        XCTAssertTrue(reopened.cycleModelSlot())
        XCTAssertEqual(reopened.activeSlotNumber, 1)
    }

    @MainActor
    func testSlotsCannotSwitchEndpointOrLeakCredentialsIntoPreferences() throws {
        let suite = "ModelSlots.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ProviderSettingsModel(defaults: defaults)
        settings.configuration.mode = .remote
        settings.configuration.baseURL = "https://EXAMPLE.test:443/v1/"
        XCTAssertTrue(settings.saveModelSlot(number: 1, name: "Первый", model: "model-a", supportsVision: false))
        settings.configuration.baseURL = "https://example.test/v1"
        XCTAssertTrue(settings.activateModelSlot(1))
        settings.configuration.baseURL = "https://other.example.test/v1"
        XCTAssertNil(settings.activeSlotNumber)
        let original = settings.configuration
        XCTAssertFalse(settings.activateModelSlot(1))
        XCTAssertFalse(settings.cycleModelSlot())
        XCTAssertEqual(settings.configuration, original)
        settings.configuration.baseURL = "https://user:credential@example.test/v1"
        XCTAssertFalse(settings.saveModelSlot(number: 2, name: "Второй", model: "model-b", supportsVision: false))
        let data = try XCTUnwrap(defaults.data(forKey: "provider.modelSlots.v1"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("credential"))
        XCTAssertEqual(settings.modelSlots.count, 1)
    }

    @MainActor
    func testInvalidOrDuplicateSlotsAreRejectedWithoutReplacingValidData() throws {
        let suite = "ModelSlots.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ProviderSettingsModel(defaults: defaults)
        XCTAssertFalse(settings.cycleModelSlot())
        XCTAssertFalse(settings.saveModelSlot(number: 1, name: "Первый", model: "demo", supportsVision: false))
        settings.configuration.mode = .remote
        settings.configuration.baseURL = "https://example.test/v1"
        XCTAssertTrue(settings.saveModelSlot(number: 1, name: "Первый", model: "model-a", supportsVision: false))
        let saved = settings.modelSlots
        for model in ["", " \n", "first\nsecond", String(repeating: "x", count: 257)] {
            XCTAssertFalse(settings.saveModelSlot(number: 1, name: "Первый", model: model, supportsVision: false))
        }
        XCTAssertFalse(settings.saveModelSlot(number: 6, name: "Шестой", model: "model", supportsVision: false))
        XCTAssertFalse(settings.saveModelSlot(number: 1, name: " ", model: "model", supportsVision: false))
        XCTAssertFalse(settings.saveModelSlot(number: 1, name: "Первый", model: "model", supportsVision: false,
                                             maxContextTokens: 1_024, reservedOutputTokens: 2_048))
        XCTAssertEqual(settings.modelSlots, saved)
        let slot = try XCTUnwrap(saved[1])
        defaults.set(try JSONEncoder().encode([slot, slot]), forKey: "provider.modelSlots.v1")
        XCTAssertTrue(ProviderSettingsModel(defaults: defaults).modelSlots.isEmpty)
        defaults.set(Data("broken".utf8), forKey: "provider.modelSlots.v1")
        XCTAssertTrue(ProviderSettingsModel(defaults: defaults).modelSlots.isEmpty)
    }
}
