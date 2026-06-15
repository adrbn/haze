import XCTest
@testable import SleepiKit

final class ItemSettingsTests: XCTestCase {
    func testTolerantDecodeMissingSpeed() throws {
        // Items saved before `speed` existed must still load (speed -> 1.0).
        let json = #"{"fps":30,"scaling":"fill"}"#.data(using: .utf8)!
        let decoded = try JSONStore.decoder.decode(ItemSettings.self, from: json)
        XCTAssertEqual(decoded.speed, 1.0)
        XCTAssertEqual(decoded.fps, 30)
        XCTAssertEqual(decoded.scaling, .fill)
    }

    func testEmptyObjectDecodesToDefaults() throws {
        let decoded = try JSONStore.decoder.decode(ItemSettings.self, from: "{}".data(using: .utf8)!)
        XCTAssertEqual(decoded.speed, 1.0)
        XCTAssertEqual(decoded.fps, 0)
        XCTAssertEqual(decoded.scaling, .fill)
    }

    func testRoundTripPreservesSpeed() throws {
        let settings = ItemSettings(fps: 24, scaling: .fit, speed: 1.5)
        let data = try JSONStore.encoder.encode(settings)
        let decoded = try JSONStore.decoder.decode(ItemSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    func testVideoRateClampMatchesUIRange() {
        XCTAssertEqual(VideoRenderer.clampRate(0.05), 0.25, accuracy: 0.0001)
        XCTAssertEqual(VideoRenderer.clampRate(10.0), 2.0, accuracy: 0.0001)
        XCTAssertEqual(VideoRenderer.clampRate(1.25), 1.25, accuracy: 0.0001)
    }
}
