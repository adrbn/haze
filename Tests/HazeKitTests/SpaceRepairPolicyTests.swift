import XCTest
@testable import HazeKit

/// The repair policy is the loop-guard around "recreate the wallpaper window
/// when it fell off the active Space". The dangerous case: a display showing a
/// full-screen Space where a desktop-level window legitimately can't live —
/// naive rebuild-on-space-change would recreate (and restart the renderer)
/// on every swipe, forever. The policy must repair once, then stand down until
/// the display reports healthy again.
final class SpaceRepairPolicyTests: XCTestCase {
    private let display: UInt32 = 42
    private let other: UInt32 = 7
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    func testHealthyWindowNeedsNothing() {
        var p = SpaceRepairPolicy()
        XCTAssertEqual(p.verdict(display: display, isOnActiveSpace: true, now: t0), .healthy)
    }

    func testOffSpaceWindowGetsRepaired() {
        var p = SpaceRepairPolicy()
        XCTAssertEqual(p.verdict(display: display, isOnActiveSpace: false, now: t0), .repair)
    }

    func testCooldownBlocksImmediateRetry() {
        var p = SpaceRepairPolicy(cooldown: 3)
        XCTAssertEqual(p.verdict(display: display, isOnActiveSpace: false, now: t0), .repair)
        XCTAssertEqual(p.verdict(display: display, isOnActiveSpace: false, now: t0.addingTimeInterval(1)), .skip)
        XCTAssertEqual(p.verdict(display: display, isOnActiveSpace: false, now: t0.addingTimeInterval(3.5)), .repair)
    }

    func testCooldownIsPerDisplay() {
        var p = SpaceRepairPolicy(cooldown: 3)
        XCTAssertEqual(p.verdict(display: display, isOnActiveSpace: false, now: t0), .repair)
        XCTAssertEqual(p.verdict(display: other, isOnActiveSpace: false, now: t0), .repair)
    }

    func testFailedRepairSuppressesDisplayEvenAfterCooldown() {
        var p = SpaceRepairPolicy(cooldown: 3)
        XCTAssertEqual(p.verdict(display: display, isOnActiveSpace: false, now: t0), .repair)
        p.repairDidFail(display: display)
        XCTAssertEqual(p.verdict(display: display, isOnActiveSpace: false, now: t0.addingTimeInterval(60)), .skip)
    }

    func testHealthyReportClearsSuppression() {
        var p = SpaceRepairPolicy(cooldown: 0)
        _ = p.verdict(display: display, isOnActiveSpace: false, now: t0)
        p.repairDidFail(display: display)
        // Display went back to a normal Space (window visible again)…
        XCTAssertEqual(p.verdict(display: display, isOnActiveSpace: true, now: t0.addingTimeInterval(10)), .healthy)
        // …so a later new full-screen Space must be repairable again.
        XCTAssertEqual(p.verdict(display: display, isOnActiveSpace: false, now: t0.addingTimeInterval(20)), .repair)
    }

    func testSuppressionIsPerDisplay() {
        var p = SpaceRepairPolicy(cooldown: 0)
        _ = p.verdict(display: display, isOnActiveSpace: false, now: t0)
        p.repairDidFail(display: display)
        XCTAssertEqual(p.verdict(display: other, isOnActiveSpace: false, now: t0.addingTimeInterval(1)), .repair)
    }

    func testResetForgetsEverything() {
        var p = SpaceRepairPolicy(cooldown: 3)
        _ = p.verdict(display: display, isOnActiveSpace: false, now: t0)
        p.repairDidFail(display: display)
        p.reset()
        XCTAssertEqual(p.verdict(display: display, isOnActiveSpace: false, now: t0.addingTimeInterval(0.1)), .repair)
    }
}
