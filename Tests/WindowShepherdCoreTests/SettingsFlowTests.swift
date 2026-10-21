import XCTest
@testable import WindowShepherdCore

@MainActor
final class FakeTarget: ShortcutApplying {
    var config = ShortcutConfig.defaults
    var applied: [ShortcutConfig] = []
    var suspends: [Bool] = []
    func apply(_ cfg: ShortcutConfig, save: Bool) { config = cfg; applied.append(cfg) }
    func suspend(_ on: Bool) { suspends.append(on) }
}

@MainActor
final class SettingsFlowTests: XCTestCase {
    var target: FakeTarget!
    var flow: SettingsFlow!
    let safariU = AppShortcut(combo: Combo("u", .alt, .cmd), app: "Safari", what: "Show Page Source")

    override func setUp() async throws {
        target = FakeTarget()
        flow = SettingsFlow(target: target, systemCheck: { _ in [] })
    }

    func testRecordSuspendsAndResumes() {
        flow.record(.action(.sixty))
        XCTAssertEqual(flow.recording, .action(.sixty))
        XCTAssertEqual(target.suspends, [true])
        flow.stopRecording()
        XCTAssertNil(flow.recording)
        XCTAssertEqual(target.suspends, [true, false])
    }

    func testCleanChangeAppliesAtOnce() {
        flow.record(.action(.sixty))
        flow.recorded(mods: [.alt, .cmd], key: "j")
        XCTAssertEqual(target.config.actions[.sixty], Combo("j", .alt, .cmd))
        XCTAssertNil(flow.recording)
    }

    func testPlainKeyKeepsListening() {
        flow.record(.action(.sixty))
        flow.recorded(mods: [.shift], key: "j")
        XCTAssertEqual(flow.recordHint, "Hold ⌃, ⌥ or ⌘ too")
        XCTAssertEqual(flow.recording, .action(.sixty))
        XCTAssertTrue(target.applied.isEmpty)
    }

    func testBlockedShowsErrorAndChangesNothing() {
        flow.record(.action(.almost))
        flow.recorded(mods: [.ctrl, .alt, .cmd], key: "f")
        XCTAssertTrue(flow.errors[Entry.action(.almost).key]?.contains("Full screen") ?? false)
        XCTAssertTrue(target.applied.isEmpty)
    }

    func testWarnNeedsKeep() {
        flow.scanFinished(ClashSources(apps: [safariU]))
        flow.record(.action(.sixty))
        flow.recorded(mods: [.alt, .cmd], key: "u")
        XCTAssertEqual(flow.pending?.warns, ["⌥⌘U — Safari: Show Page Source. Yours will win."])
        XCTAssertTrue(target.applied.isEmpty, "nothing live while a choice is pending")
        flow.keep()
        XCTAssertEqual(target.config.actions[.sixty]?.key, "u")
        XCTAssertNil(flow.pending)
    }

    func testCancelKeepsOld() {
        flow.scanFinished(ClashSources(apps: [safariU]))
        flow.record(.action(.sixty))
        flow.recorded(mods: [.alt, .cmd], key: "u")
        flow.cancel()
        XCTAssertNil(flow.pending)
        XCTAssertEqual(target.config.actions[.sixty]?.key, "h")
    }

    func testPendingWaitsForScan() {
        flow.scanStarted()
        flow.record(.action(.sixty))
        flow.recorded(mods: [.alt, .cmd], key: "u")
        XCTAssertEqual(flow.pending?.waiting, true)
        flow.keep()
        XCTAssertTrue(target.applied.isEmpty, "Keep is ignored while waiting")
        flow.scanFinished(ClashSources(apps: [safariU]))
        XCTAssertEqual(flow.pending?.waiting, false, "the scan found a clash: now it asks")
        XCTAssertTrue(target.applied.isEmpty)
    }

    func testPendingAppliesWhenScanFindsNothing() {
        flow.scanStarted()
        flow.record(.action(.sixty))
        flow.recorded(mods: [.alt, .cmd], key: "j")
        flow.scanFinished(ClashSources())
        XCTAssertNil(flow.pending)
        XCTAssertEqual(target.config.actions[.sixty]?.key, "j")
    }

    func testResetIsDirectEvenWithWarnings() {
        target.config.actions[.center] = Combo("k", .alt, .cmd)
        flow.scanFinished(ClashSources(apps: [AppShortcut(combo: Combo("c", .alt, .cmd), app: "Safari", what: "Console")]))
        flow.reset(.action(.center))
        XCTAssertEqual(target.config.actions[.center]?.key, "c")
        XCTAssertNil(flow.pending)
    }

    func testResetAll() {
        target.config.actions[.sixty] = Combo("j", .alt, .cmd)
        target.config.wholeApp = .shift
        target.config.nextScreen = .ctrl
        flow.resetAll()
        XCTAssertEqual(target.config, .defaults)
    }

    func testModifierToggles() {
        flow.toggleScreenMod(.ctrl)   // ⌃ is the whole-app modifier: blocked
        XCTAssertNotNil(flow.errors[Entry.screenBase.key])
        XCTAssertEqual(target.config.screenBase, [.alt, .cmd])
        flow.setModifier(.nextScreen, .alt)   // ⌥ is in the screen base: blocked
        XCTAssertNotNil(flow.errors[Entry.nextScreen.key])
        target.config.nextScreen = .ctrl            // swap the two "add a key" modifiers
        flow.setModifier(.wholeApp, .shift)
        XCTAssertEqual(target.config.wholeApp, .shift, "\(flow.errors)")
    }

    func testPickingTheOtherExtraKeySwapsThemInOneClick() {
        flow.setModifier(.wholeApp, .shift)   // ⇧ was the next-screen key
        XCTAssertEqual(target.config.wholeApp, .shift, "\(flow.errors)")
        XCTAssertEqual(target.config.nextScreen, .ctrl)
        flow.setModifier(.wholeApp, .ctrl)    // and back, from the other row's side
        XCTAssertEqual(target.config.wholeApp, .ctrl)
        XCTAssertEqual(target.config.nextScreen, .shift)
        flow.setModifier(.nextScreen, .ctrl)
        XCTAssertEqual(target.config.nextScreen, .ctrl, "\(flow.errors)")
        XCTAssertEqual(target.config.wholeApp, .shift)
    }

    func testAnExtraKeyThatsAScreenKeySaysSoInPlainWords() {
        flow.setModifier(.wholeApp, .alt)
        XCTAssertEqual(flow.errors[Entry.wholeApp.key],
                       "⌥ is one of the screen keys (⌥⌘ plus a number), so it can't also be an extra key. To use it here, take ⌥ out of the screen keys first.")
        XCTAssertEqual(target.config, .defaults)
        flow.toggleScreenMod(.shift)
        XCTAssertEqual(flow.errors[Entry.screenBase.key],
                       "⇧ is the extra key for the next screen, so it can't also be a screen key.")
    }

    func testCloseDropsPendingAndRecording() {
        flow.scanFinished(ClashSources(apps: [safariU]))
        flow.record(.action(.sixty))
        flow.recorded(mods: [.alt, .cmd], key: "u")
        flow.record(.action(.almost))
        flow.closed()
        XCTAssertNil(flow.pending)
        XCTAssertNil(flow.recording)
        XCTAssertEqual(target.suspends.last, false)
    }

    func testProgressText() {
        flow.scanStarted()
        flow.scanProgress(ClashSources(), done: 3, total: 9)
        XCTAssertEqual(flow.statusText, "Checking your open apps for clashes… 3 of 9")
        flow.scanFinished(ClashSources())
        XCTAssertEqual(flow.statusText, "Checked macOS, your open apps and popular apps.")
    }
}
