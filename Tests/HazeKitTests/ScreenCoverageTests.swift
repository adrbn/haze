import XCTest
import CoreGraphics
@testable import HazeKit

final class ScreenCoverageTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testEmptyScreensIsNotCovered() {
        XCTAssertFalse(ScreenCoverage.allScreensCovered(screens: [], windows: [screen]))
    }

    func testNoWindowsIsNotCovered() {
        XCTAssertFalse(ScreenCoverage.allScreensCovered(screens: [screen], windows: []))
    }

    func testFullCoverWindowCovers() {
        XCTAssertTrue(ScreenCoverage.allScreensCovered(screens: [screen], windows: [screen]))
    }

    func testLargerWindowCovers() {
        let big = CGRect(x: -10, y: -10, width: 2000, height: 1200)
        XCTAssertTrue(ScreenCoverage.allScreensCovered(screens: [screen], windows: [big]))
    }

    func testPartialWindowDoesNotCover() {
        let half = CGRect(x: 0, y: 0, width: 960, height: 1080)
        XCTAssertFalse(ScreenCoverage.allScreensCovered(screens: [screen], windows: [half]))
    }

    func testWithinToleranceCovers() {
        // Window 1px short on each side — should still count as covered.
        let almost = CGRect(x: 1, y: 1, width: 1918, height: 1078)
        XCTAssertTrue(ScreenCoverage.allScreensCovered(screens: [screen], windows: [almost], tolerance: 2))
    }

    func testBeyondToleranceDoesNotCover() {
        let almost = CGRect(x: 10, y: 10, width: 1900, height: 1060)
        XCTAssertFalse(ScreenCoverage.allScreensCovered(screens: [screen], windows: [almost], tolerance: 2))
    }

    func testAllScreensMustBeCovered() {
        let second = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        // Only the first screen is covered.
        XCTAssertFalse(ScreenCoverage.allScreensCovered(screens: [screen, second], windows: [screen]))
        // Both covered.
        XCTAssertTrue(ScreenCoverage.allScreensCovered(screens: [screen, second], windows: [screen, second]))
    }
}
