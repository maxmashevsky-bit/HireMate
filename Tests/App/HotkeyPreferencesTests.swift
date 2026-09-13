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

    @MainActor
    func testFrameFromAnotherSpaceIsClampedToVisibleScreen() throws {
        let visible = NSRect(x: 0, y: 79, width: 1_440, height: 790)
        let displaced = NSRect(x: 263, y: -593, width: 860, height: 620)

        let result = try XCTUnwrap(OverlayPreferences.clampedFrame(
            displaced, to: visible, minimumSize: NSSize(width: 640, height: 500)
        ))

        XCTAssertEqual(result, NSRect(x: 263, y: 79, width: 860, height: 620))
    }

    @MainActor
    func testFrameClampRejectsNonFiniteGeometry() {
        let invalid = NSRect(x: CGFloat.infinity, y: 0, width: 860, height: 620)
        XCTAssertNil(OverlayPreferences.clampedFrame(
            invalid, to: NSRect(x: 0, y: 0, width: 1_440, height: 900),
            minimumSize: NSSize(width: 640, height: 500)
        ))
    }
}
