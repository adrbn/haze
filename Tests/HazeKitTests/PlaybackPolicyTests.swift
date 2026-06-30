import XCTest
@testable import HazeKit

final class PlaybackPolicyTests: XCTestCase {
    func testDefaultRenders() {
        XCTAssertTrue(PlaybackPolicy().shouldRender)
    }

    func testUserPauseAlwaysWins() {
        var p = PlaybackPolicy()
        p.userPaused = true
        XCTAssertFalse(p.shouldRender)
    }

    func testSystemSleepStops() {
        var p = PlaybackPolicy()
        p.systemAsleep = true
        XCTAssertFalse(p.shouldRender)
    }

    func testScreenLockStops() {
        var p = PlaybackPolicy()
        p.screenLocked = true
        XCTAssertFalse(p.shouldRender)
    }

    func testOcclusionRespectsPreference() {
        var on = PlaybackPolicy(occluded: true, pauseWhenOccluded: true)
        XCTAssertFalse(on.shouldRender)

        var off = PlaybackPolicy(occluded: true, pauseWhenOccluded: false)
        XCTAssertTrue(off.shouldRender)
        _ = on; _ = off
    }

    func testDisplaySleepRespectsPreference() {
        XCTAssertFalse(PlaybackPolicy(displayAsleep: true, pauseOnDisplaySleep: true).shouldRender)
        XCTAssertTrue(PlaybackPolicy(displayAsleep: true, pauseOnDisplaySleep: false).shouldRender)
    }

    func testBatteryRespectsPreference() {
        XCTAssertTrue(PlaybackPolicy(onBattery: true, pauseOnBattery: false).shouldRender)
        XCTAssertFalse(PlaybackPolicy(onBattery: true, pauseOnBattery: true).shouldRender)
    }

    func testLowPowerModeRespectsPreference() {
        XCTAssertFalse(PlaybackPolicy(lowPowerMode: true, pauseInLowPowerMode: true).shouldRender)
        XCTAssertTrue(PlaybackPolicy(lowPowerMode: true, pauseInLowPowerMode: false).shouldRender)
    }

    func testApplyPreferencesPullsFromSettings() {
        var settings = AppSettings.default
        settings.pauseWhenOccluded = false
        settings.pauseOnBattery = true
        var p = PlaybackPolicy()
        p.applyPreferences(settings)
        XCTAssertFalse(p.pauseWhenOccluded)
        XCTAssertTrue(p.pauseOnBattery)
    }

    // MARK: Screensaver self-gate (externally-driven host path)

    // An orphaned screensaver instance — legacyScreenSaver abandoned the view
    // without calling stopAnimation, so per-Space / per-idle instances pile up —
    // must only draw while genuinely visible on an awake display. Without this it
    // renders at full FPS for days and overheats the Mac.
    func testSaverDrawsWhenVisibleAndAwake() {
        XCTAssertTrue(PlaybackPolicy.saverShouldDraw(visible: true, displayAsleep: false))
    }

    func testSaverPausesWhenNotVisible() {
        XCTAssertFalse(PlaybackPolicy.saverShouldDraw(visible: false, displayAsleep: false))
    }

    func testSaverPausesWhenDisplayAsleep() {
        XCTAssertFalse(PlaybackPolicy.saverShouldDraw(visible: true, displayAsleep: true))
    }
}
