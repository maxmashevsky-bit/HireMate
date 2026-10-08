import XCTest
import Carbon

private struct FixedSecureInputChecker: SecureInputChecking {
    let enabled: Bool
    func isSecureInputEnabled() -> Bool { enabled }
}

final class HotkeyPreferencesTests: XCTestCase {
    @MainActor
    func testQuickActionHintsFollowAssignedNumericCustomAndDisabledShortcuts() throws {
        let suite = "QuickActionHints.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = OverlayPreferences(defaults: defaults)
        XCTAssertEqual(preferences.quickActionShortcutLabel(slot: 1), "⌘1")
        XCTAssertEqual(preferences.quickActionShortcutLabel(slot: 5), "⌘5")
        preferences.setHotkeyOverride(HotkeyOverride(key: .m, usesShift: true), for: .quick1)
        XCTAssertEqual(preferences.quickActionShortcutLabel(slot: 1), "⌘⇧M")
        preferences.setHotkeyEnabled(false, for: .quick5)
        XCTAssertEqual(preferences.quickActionShortcutLabel(slot: 5), "Отключено")
        preferences.shortcutsEnabled = false
        XCTAssertEqual(preferences.quickActionShortcutLabel(slot: 1), "Горячие клавиши отключены")
    }

    @MainActor
    func testModelCycleShortcutRequiresOptInPersistsAndResetsToDisabled() throws {
        let suite = "ModelCycleHotkey.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = OverlayPreferences(defaults: defaults)
        XCTAssertFalse(preferences.isHotkeyEnabled(.cycleModels))
        XCTAssertEqual(preferences.shortcutLabel(for: .cycleModels), "Отключено")
        preferences.setHotkeyEnabled(true, for: .cycleModels)
        let reopened = OverlayPreferences(defaults: defaults)
        XCTAssertTrue(reopened.isHotkeyEnabled(.cycleModels))
        XCTAssertEqual(reopened.shortcutLabel(for: .cycleModels), "⌘⇧M")
        reopened.resetAllHotkeys()
        XCTAssertFalse(OverlayPreferences(defaults: defaults).isHotkeyEnabled(.cycleModels))
    }

    @MainActor
    func testStatusIndicatorVisibilityAndCornerPersistWithSafeDefaults() throws {
        let suite = "OverlayStatus.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = OverlayPreferences(defaults: defaults)
        XCTAssertTrue(preferences.showsStatusIndicator)
        XCTAssertEqual(preferences.statusCorner, .bottomRight)
        preferences.showsStatusIndicator = false
        for corner in OverlayStatusCorner.allCases {
            preferences.statusCorner = corner
            let restored = OverlayPreferences(defaults: defaults)
            XCTAssertEqual(restored.statusCorner, corner)
            XCTAssertFalse(restored.showsStatusIndicator)
        }
        defaults.set("unknown", forKey: "overlay.statusCorner")
        defaults.set("invalid", forKey: "overlay.showsStatusIndicator")
        let corrupt = OverlayPreferences(defaults: defaults)
        XCTAssertEqual(corrupt.statusCorner, .bottomRight)
        XCTAssertTrue(corrupt.showsStatusIndicator)
    }

    func testHistoryFollowingUsesLatestEdgeForSelectedMessageOrder() {
        let nearTop = HistoryViewport(offset: 30, height: 500, contentHeight: 2000)
        XCTAssertTrue(nearTop.nearLatest(order: .newestTop))
        XCTAssertFalse(nearTop.nearLatest(order: .newestBottom))
        let nearBottom = HistoryViewport(offset: 1470, height: 500, contentHeight: 2000)
        XCTAssertFalse(nearBottom.nearLatest(order: .newestTop))
        XCTAssertTrue(nearBottom.nearLatest(order: .newestBottom))
        let shortHistory = HistoryViewport(height: 500, contentHeight: 100)
        XCTAssertTrue(shortHistory.nearLatest(order: .newestTop))
        XCTAssertTrue(shortHistory.nearLatest(order: .newestBottom))
    }
    @MainActor
    func testTeleprompterColorsPersistRestoreCorruptValuesAndReset() throws {
        let suite = "TeleprompterColors.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let colors = TeleprompterAppearance(defaults: defaults)
        XCTAssertEqual(colors.background.hex, "#111111")
        XCTAssertEqual(colors.neighbor.hex, "#FFFFFF")
        XCTAssertEqual(colors.active.hex, "#FFFFFF")
        colors.background = .init(rgb: 0x222233)
        colors.neighbor = .init(rgb: 0xAABBCC)
        colors.active = .init(rgb: 0x00FF00)
        let restored = TeleprompterAppearance(defaults: defaults)
        XCTAssertEqual(restored.background, colors.background)
        XCTAssertEqual(restored.neighbor, colors.neighbor)
        XCTAssertEqual(restored.active, colors.active)
        defaults.set("#FFFF", forKey: "teleprompter.activeColor")
        XCTAssertEqual(TeleprompterAppearance(defaults: defaults).active.hex, "#FFFFFF")
        restored.reset()
        let reset = TeleprompterAppearance(defaults: defaults)
        XCTAssertEqual(reset.background.hex, "#111111")
        XCTAssertEqual(reset.neighbor.hex, "#FFFFFF")
        XCTAssertEqual(reset.active.hex, "#FFFFFF")
    }

    @MainActor
    func testPanelLayoutMovesReordersHidesRestoresAndPersists() throws {
        let suite = "PanelLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = OverlayPreferences(defaults: defaults)
        preferences.movePanelTool(.screenshot, to: .header, before: .provider)
        XCTAssertEqual(preferences.panelLayout.header.prefix(3), [.audio, .screenshot, .provider])
        XCTAssertFalse(preferences.panelLayout.input.contains(.screenshot))
        preferences.movePanelTool(.headerNotes, to: .hidden)
        XCTAssertEqual(preferences.panelLayout.hidden, [.headerNotes])
        preferences.movePanelTool(.headerNotes, to: .input, before: .context)
        XCTAssertTrue(preferences.panelLayout.hidden.isEmpty)
        XCTAssertEqual(preferences.panelLayout.input.first, .headerNotes)
        let beforeSelfDrop = preferences.panelLayout
        preferences.movePanelTool(.context, to: .input, before: .context)
        XCTAssertEqual(preferences.panelLayout, beforeSelfDrop)
        XCTAssertEqual(OverlayPreferences(defaults: defaults).panelLayout, preferences.panelLayout)
        let all = preferences.panelLayout.header + preferences.panelLayout.input + preferences.panelLayout.hidden
        XCTAssertEqual(all.count, MeetingPanelTool.allCases.count)
        XCTAssertEqual(Set(all), Set(MeetingPanelTool.allCases))
        preferences.showsQuickActions = false
        preferences.resetPanelLayout()
        XCTAssertEqual(OverlayPreferences(defaults: defaults).panelLayout, .standard)
        XCTAssertTrue(preferences.showsQuickActions)
    }

    func testPanelLayoutRejectsMissingDuplicateAndUnknownTools() throws {
        let invalidLayouts = [
            Data("{\"header\":[],\"input\":[],\"hidden\":[]}".utf8),
            Data("{\"header\":[\"unknown\"],\"input\":[],\"hidden\":[]}".utf8),
            Data("invalid JSON".utf8)
        ]
        for data in invalidLayouts { XCTAssertEqual(MeetingPanelLayout.restore(data), .standard) }
        var duplicate = MeetingPanelLayout.standard
        duplicate[.hidden] = [.audio]
        XCTAssertEqual(MeetingPanelLayout.restore(try JSONEncoder().encode(duplicate)), .standard)
    }

    func testHistoryPagesMovePartOfViewportInsteadOfJumpingToEnds() {
        let viewport = HistoryViewport(offset: 1200, height: 1000, contentHeight: 5000)
        XCTAssertEqual(viewport.pagedOffset(direction: -1), 400)
        XCTAssertEqual(viewport.pagedOffset(direction: 1), 2000)
        XCTAssertFalse(viewport.nearBottom)
        XCTAssertEqual(viewport.pagedOffset(direction: 0), 1200)
    }

    func testHistoryPagingClampsAtContentEdgesAndHandlesShortHistory() {
        XCTAssertEqual(HistoryViewport(offset: 100, height: 500, contentHeight: 2000).pagedOffset(direction: -1), 0)
        let bottom = HistoryViewport(offset: 1400, height: 500, contentHeight: 2000)
        XCTAssertEqual(bottom.pagedOffset(direction: 1), 1500)
        XCTAssertFalse(bottom.nearBottom)
        XCTAssertTrue(HistoryViewport(offset: 1470, height: 500, contentHeight: 2000).nearBottom)
        XCTAssertEqual(HistoryViewport(height: 500, contentHeight: 100).pagedOffset(direction: 1), 0)
        XCTAssertEqual(HistoryViewport().pagedOffset(direction: -1), 0)
    }

    func testStreamingDoesNotMoveHistoryWhileUserReadsEarlierMessages() {
        var policy = HistoryScrollPolicy()
        XCTAssertTrue(policy.receivedContent(automatically: true))
        policy.beginUserScroll()
        for _ in 0..<100 {
            XCTAssertFalse(policy.receivedContent(automatically: true))
        }
        policy.endUserScroll(nearLatest: false)
        XCTAssertFalse(policy.receivedContent(automatically: true))
        XCTAssertTrue(policy.hasUnreadContent)
        policy.jumpToLatest()
        XCTAssertFalse(policy.hasUnreadContent)
        XCTAssertTrue(policy.receivedContent(automatically: true))
    }

    func testReturningToBottomResumesFollowingButDisabledAutoscrollDoesNotJump() {
        var policy = HistoryScrollPolicy()
        policy.beginUserScroll()
        policy.endUserScroll(nearLatest: true)
        XCTAssertTrue(policy.receivedContent(automatically: true))
        XCTAssertFalse(policy.receivedContent(automatically: false))
        XCTAssertTrue(policy.hasUnreadContent)
        policy.jumpToLatest()
        XCTAssertFalse(policy.hasUnreadContent)
        XCTAssertFalse(policy.receivedContent(automatically: false))
    }

    @MainActor
    func testMeetingPanelPreferencesPersist() throws {
        let suite = "OverlayScroll.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = OverlayPreferences(defaults: defaults)
        XCTAssertTrue(preferences.smartAutoScroll)
        XCTAssertTrue(preferences.showsQuickActions)
        XCTAssertFalse(preferences.compactQuickActions)
        preferences.smartAutoScroll = false
        preferences.showsQuickActions = false
        preferences.compactQuickActions = true
        let restored = OverlayPreferences(defaults: defaults)
        XCTAssertFalse(restored.smartAutoScroll)
        XCTAssertFalse(restored.showsQuickActions)
        XCTAssertTrue(restored.compactQuickActions)
    }

    @MainActor
    func testDefaultBindingsAreUniqueInEveryPreset() {
        for preset in ShortcutPreset.allCases {
            let bindings = GlobalHotkeyService.Action.allCases.map {
                GlobalHotkeyService.binding(for: $0, preset: preset)
            }
            XCTAssertEqual(Set(bindings).count, bindings.count, preset.rawValue)
        }
    }

    @MainActor
    func testSpeechShortcutsMatchMainSpecification() {
        let play = GlobalHotkeyService.binding(for: .toggleLastSpeech, preset: .command)
        let automatic = GlobalHotkeyService.binding(for: .toggleAutomaticSpeech, preset: .command)
        XCTAssertEqual(play.keyCode, HotkeyKey.s.keyCode)
        XCTAssertEqual(play.modifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(automatic.keyCode, HotkeyKey.s.keyCode)
        XCTAssertEqual(automatic.modifiers, UInt32(cmdKey | optionKey))
    }

    @MainActor
    func testSpeechSettingsPersistAndFencedCodeCanBeSkipped() throws {
        let suite = "SpeechSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var speech = SpeechModel(defaults: defaults)
        speech.autoRead = true
        speech.skipCodeBlocks = false
        speech.volume = 0.4
        speech.rate = 0.48
        speech = SpeechModel(defaults: defaults)
        XCTAssertTrue(speech.autoRead)
        XCTAssertFalse(speech.skipCodeBlocks)
        XCTAssertEqual(speech.volume, 0.4, accuracy: 0.001)
        XCTAssertEqual(speech.rate, 0.48, accuracy: 0.001)

        let markdown = "Вступление\n```go\nfmt.Println(1)\n```\nИтог\n~~~~\nсекретный код\n~~~~"
        XCTAssertEqual(SpeechModel.removingFencedCode(from: markdown), "Вступление\nИтог")
    }

    @MainActor
    func testOverridesDetectCollisionButKeepModifiersDistinct() {
        let plain = HotkeyOverride(key: .h, usesShift: false)
        let first = GlobalHotkeyService.binding(for: .toggle, preset: .commandOption, override: plain)
        XCTAssertEqual(first, GlobalHotkeyService.binding(for: .focus, preset: .commandOption, override: plain))
        XCTAssertNotEqual(first, GlobalHotkeyService.binding(
            for: .focus, preset: .commandOption, override: HotkeyOverride(key: .h, usesShift: true)))
        XCTAssertNotEqual(first, GlobalHotkeyService.binding(for: .scrollUp, preset: .commandOption, override: plain))
        XCTAssertNotEqual(first, GlobalHotkeyService.binding(for: .focus, preset: .controlOption, override: plain))
    }

    @MainActor
    func testUnavailableFocusShortcutOffersMenuRecovery() throws {
        let suite = "HotkeyRecovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = OverlayPreferences(defaults: defaults)
        XCTAssertTrue(preferences.restoreInputHint(focusShortcutRegistered: false).contains("В меню приложения"))
        XCTAssertEqual(preferences.restoreInputHint(focusShortcutRegistered: true), "Вернуть ввод: ⌘D")
        preferences.shortcutsEnabled = false
        XCTAssertTrue(preferences.restoreInputHint(focusShortcutRegistered: true).contains("В меню приложения"))
        let service = GlobalHotkeyService()
        service.configure(enabled: false, preset: .commandOption, overrides: [:]) { _ in
            XCTFail("Отключённые сочетания не должны вызывать действие")
        }
        XCTAssertTrue(service.registeredActions.isEmpty)
        XCTAssertEqual(service.registeredCount, 0)
    }

    @MainActor
    func testShortcutLabelsFollowOverridesPresetAndReset() throws {
        let suite = "HotkeyLabels.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = OverlayPreferences(defaults: defaults)
        XCTAssertEqual(preferences.shortcutLabel(for: .focus), "⌘D")
        preferences.setHotkeyOverride(HotkeyOverride(key: .h, usesShift: true), for: .focus)
        XCTAssertEqual(preferences.shortcutLabel(for: .focus), "⌘⇧H")
        preferences.shortcutPreset = .controlOption
        XCTAssertEqual(preferences.shortcutLabel(for: .focus), "⌃⌥⇧H")
        preferences.setHotkeyOverride(nil, for: .focus)
        XCTAssertEqual(preferences.shortcutLabel(for: .focus), "⌃⌥D")
        preferences.setHotkeyOverride(HotkeyOverride(key: .h, usesShift: false), for: .scrollUp)
        XCTAssertEqual(preferences.shortcutLabel(for: .scrollUp), "⌃⌥⌘H")
    }

    @MainActor
    func testIndividualDisableAndResetAllPersist() throws {
        let suite = "HotkeyDisable.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = OverlayPreferences(defaults: defaults)
        preferences.setHotkeyEnabled(false, for: .notes)
        preferences.setHotkeyOverride(HotkeyOverride(key: .h, usesShift: true), for: .focus)
        preferences.shortcutPreset = .controlOption

        let restored = OverlayPreferences(defaults: defaults)
        XCTAssertFalse(restored.isHotkeyEnabled(.notes))
        XCTAssertEqual(restored.shortcutLabel(for: .notes), "Отключено")
        restored.resetAllHotkeys()
        XCTAssertTrue(restored.isHotkeyEnabled(.notes))
        XCTAssertNil(restored.hotkeyOverride(for: .focus))
        XCTAssertEqual(restored.shortcutPreset, .command)
    }

    @MainActor
    func testGeometryStepsPersistAndInvalidStoredValuesAreClamped() throws {
        let suite = "OverlaySteps.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = OverlayPreferences(defaults: defaults)
        XCTAssertEqual(preferences.moveStep, 50)
        preferences.moveStep = 75
        preferences.resizeStep = 125
        preferences = OverlayPreferences(defaults: defaults)
        XCTAssertEqual(preferences.moveStep, 75)
        XCTAssertEqual(preferences.resizeStep, 125)
        defaults.set(Double.infinity, forKey: "overlay.moveStep")
        defaults.set(500.0, forKey: "overlay.resizeStep")
        preferences = OverlayPreferences(defaults: defaults)
        XCTAssertEqual(preferences.moveStep, 50)
        XCTAssertEqual(preferences.resizeStep, 200)
    }

    @MainActor
    func testAutoScrollSpeedPersistsAndInvalidValuesCannotCreateUnsafeAnimation() throws {
        let suite = "OverlayScrollSpeed.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = OverlayPreferences(defaults: defaults)
        XCTAssertEqual(preferences.autoScrollSpeed, 1)
        let normalDuration = preferences.autoScrollAnimationDuration
        preferences.autoScrollSpeed = 2
        XCTAssertEqual(OverlayPreferences(defaults: defaults).autoScrollSpeed, 2)
        XCTAssertLessThan(preferences.autoScrollAnimationDuration, normalDuration)
        preferences.autoScrollSpeed = 0
        XCTAssertEqual(preferences.autoScrollSpeed, 0.25)
        XCTAssertGreaterThan(preferences.autoScrollAnimationDuration, normalDuration)
        preferences.autoScrollSpeed = .nan
        XCTAssertEqual(preferences.autoScrollSpeed, 1)
        XCTAssertEqual(OverlayPreferences(defaults: defaults).autoScrollSpeed, 1)
        defaults.set(Double.infinity, forKey: "overlay.autoScrollSpeed")
        XCTAssertEqual(OverlayPreferences(defaults: defaults).autoScrollSpeed, 1)
        defaults.set(50.0, forKey: "overlay.autoScrollSpeed")
        XCTAssertEqual(OverlayPreferences(defaults: defaults).autoScrollSpeed, 2)
    }

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
    func testFrameFitsSmallDisplayAtNegativeCoordinates() throws {
        let visible = NSRect(x: -600, y: -450, width: 600, height: 450)
        let result = try XCTUnwrap(OverlayPreferences.clampedFrame(
            NSRect(x: 100, y: 100, width: 860, height: 620), to: visible,
            minimumSize: NSSize(width: 640, height: 500)
        ))
        XCTAssertEqual(result, visible)
    }

    @MainActor
    func testFrameKeepsPointSizeOnDisplayAbovePrimary() throws {
        let visible = NSRect(x: 0, y: 900, width: 1920, height: 1080)
        let result = try XCTUnwrap(OverlayPreferences.clampedFrame(
            NSRect(x: 530, y: 1130, width: 860, height: 620), to: visible,
            minimumSize: NSSize(width: 640, height: 500)
        ))
        XCTAssertEqual(result, NSRect(x: 530, y: 1130, width: 860, height: 620))
    }

    @MainActor
    func testOffscreenFrameReturnsToPreferredDisplay() {
        let screens = [
            NSRect(x: -1440, y: 0, width: 1440, height: 900),
            NSRect(x: 0, y: 0, width: 1440, height: 900)
        ]
        let frame = NSRect(x: 3000, y: -900, width: 860, height: 620)
        XCTAssertEqual(OverlayPreferences.targetScreenIndex(
            for: frame, visibleFrames: screens, preferredIndex: 1), 1)
        XCTAssertEqual(OverlayPreferences.targetScreenIndex(
            for: frame, visibleFrames: screens, preferredIndex: 5), 0)
        XCTAssertNil(OverlayPreferences.targetScreenIndex(
            for: frame, visibleFrames: [], preferredIndex: 0))
    }

    @MainActor
    func testLargestOverlapWinsAndTieKeepsPreferredDisplay() {
        let screens = [
            NSRect(x: -1000, y: 0, width: 1000, height: 900),
            NSRect(x: 0, y: 0, width: 1000, height: 900)
        ]
        XCTAssertEqual(OverlayPreferences.targetScreenIndex(
            for: NSRect(x: -700, y: 100, width: 800, height: 500),
            visibleFrames: screens, preferredIndex: 1), 0)
        XCTAssertEqual(OverlayPreferences.targetScreenIndex(
            for: NSRect(x: -400, y: 100, width: 800, height: 500),
            visibleFrames: screens, preferredIndex: 1), 1)
    }

    @MainActor
    func testFrameClampRejectsNonFiniteGeometry() {
        let invalid = NSRect(x: CGFloat.infinity, y: 0, width: 860, height: 620)
        XCTAssertNil(OverlayPreferences.clampedFrame(
            invalid, to: NSRect(x: 0, y: 0, width: 1_440, height: 900),
            minimumSize: NSSize(width: 640, height: 500)
        ))
    }

    @MainActor
    func testSecureInputBlocksHotkeyDispatchAndDiagnosticsMark() {
        let blocked = GlobalHotkeyService(secureInputChecker: FixedSecureInputChecker(enabled: true))
        XCTAssertFalse(blocked.dispatch(.toggle))
        XCTAssertNil(blocked.lastTriggeredAction)
        XCTAssertNil(blocked.lastTriggeredAt)

        let allowed = GlobalHotkeyService(secureInputChecker: FixedSecureInputChecker(enabled: false))
        XCTAssertTrue(allowed.dispatch(.toggle))
        XCTAssertEqual(allowed.lastTriggeredAction, .toggle)
        XCTAssertNotNil(allowed.lastTriggeredAt)
        allowed.clearLastTrigger()
        XCTAssertNil(allowed.lastTriggeredAction)
        XCTAssertNil(allowed.lastTriggeredAt)
    }
}
