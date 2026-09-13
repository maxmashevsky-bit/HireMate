import XCTest

final class HotkeyPreferencesTests: XCTestCase {
    @MainActor
    func testIndividualOverridePersistsAndCanBeReset() throws {
        let suite = "HotkeyPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = OverlayPreferences(defaults: defaults)
        let override = HotkeyOverride(key: .h, usesShift: true)
        preferences.setHotkeyOverride(override, for: .toggle)

        let restored = OverlayPreferences(defaults: defaults)
        XCTAssertEqual(restored.hotkeyOverride(for: .toggle), override)
        restored.setHotkeyOverride(nil, for: .toggle)
        XCTAssertNil(OverlayPreferences(defaults: defaults).hotkeyOverride(for: .toggle))
    }

    @MainActor
    func testInvalidStoredOverrideFallsBackToDefault() throws {
        let suite = "HotkeyPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([String(GlobalHotkeyService.Action.toggle.rawValue): "unknown|4"],
                     forKey: "overlay.hotkeyOverrides")

        let preferences = OverlayPreferences(defaults: defaults)
        XCTAssertNil(preferences.hotkeyOverride(for: .toggle))
        XCTAssertEqual(GlobalHotkeyService.Action.toggle.defaultKey, .b)
    }
}
