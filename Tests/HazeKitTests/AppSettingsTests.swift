import XCTest
@testable import HazeKit

final class AppSettingsTests: XCTestCase {
    func testDefaults() {
        let s = AppSettings.default
        XCTAssertTrue(s.pauseWhenOccluded)
        XCTAssertTrue(s.pauseOnDisplaySleep)
        XCTAssertFalse(s.pauseOnBattery)
        XCTAssertTrue(s.pauseInLowPowerMode)
        XCTAssertEqual(s.globalFPSCap, 0)
        XCTAssertNil(s.wallpaperItemID)
    }

    func testCodableRoundTrip() throws {
        var s = AppSettings.default
        s.wallpaperItemID = UUID()
        s.globalFPSCap = 30
        s.pauseOnBattery = true
        let data = try JSONStore.encoder.encode(s)
        let decoded = try JSONStore.decoder.decode(AppSettings.self, from: data)
        XCTAssertEqual(s, decoded)
    }

    func testForwardCompatibleDecodingFillsMissingKeys() throws {
        // Only one key present — everything else must fall back to defaults.
        let json = #"{"version":1}"#.data(using: .utf8)!
        let decoded = try JSONStore.decoder.decode(AppSettings.self, from: json)
        XCTAssertEqual(decoded.pauseWhenOccluded, AppSettings.default.pauseWhenOccluded)
        XCTAssertEqual(decoded.globalFPSCap, AppSettings.default.globalFPSCap)
        XCTAssertNil(decoded.wallpaperItemID)
    }

    func testEmptyObjectDecodes() throws {
        let json = "{}".data(using: .utf8)!
        XCTAssertNoThrow(try JSONStore.decoder.decode(AppSettings.self, from: json))
    }
}
