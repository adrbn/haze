import XCTest
import AppKit
@testable import HazeKit

/// Covers the session-resume signal: the wallpaper windows lose their
/// live-through-Space-slide compositing treatment when the login/display
/// session is torn down (sleep, screen lock), so `PowerMonitor` has to tell the
/// display layer to rebuild once things are back.
@MainActor
final class PowerMonitorTests: XCTestCase {
    private func makeMonitor() -> PowerMonitor {
        let monitor = PowerMonitor(settings: .default)
        monitor.sessionResumeDelay = 0.05
        return monitor
    }

    private func settle(_ seconds: TimeInterval = 0.25) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func testWakeTriggersSessionResume() async throws {
        let monitor = makeMonitor()
        var calls = 0
        monitor.onSessionResumed = { calls += 1 }

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await settle()

        XCTAssertEqual(calls, 1)
    }

    func testDisplayWakeTriggersSessionResume() async throws {
        let monitor = makeMonitor()
        var calls = 0
        monitor.onSessionResumed = { calls += 1 }

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await settle()

        XCTAssertEqual(calls, 1)
    }

    /// Wake / screens-wake / unlock arrive together in a burst; rebuilding the
    /// wallpaper three times in a row would restart it three times.
    func testResumeNotificationsCoalesceIntoOneCallback() async throws {
        let monitor = makeMonitor()
        var calls = 0
        monitor.onSessionResumed = { calls += 1 }

        let center = NSWorkspace.shared.notificationCenter
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await settle()

        XCTAssertEqual(calls, 1)
    }

    /// Going *to* sleep must not fire it — only coming back.
    func testSleepDoesNotTriggerSessionResume() async throws {
        let monitor = makeMonitor()
        var calls = 0
        monitor.onSessionResumed = { calls += 1 }

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        try await settle()

        XCTAssertEqual(calls, 0)
    }

    /// The existing render gating must keep working alongside the new signal.
    func testWakeClearsSystemAsleepFlag() async throws {
        let monitor = makeMonitor()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertTrue(monitor.policy.systemAsleep)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertFalse(monitor.policy.systemAsleep)
    }
}
