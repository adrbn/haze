import XCTest
@testable import SleepiKit

final class GradientConfigTests: XCTestCase {
    func testHexParsingSixDigits() {
        let c = RGBAColor.hex("#FF8000")
        XCTAssertEqual(c.r, 1.0, accuracy: 0.001)
        XCTAssertEqual(c.g, 128.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.b, 0.0, accuracy: 0.001)
        XCTAssertEqual(c.a, 1.0, accuracy: 0.001)
    }

    func testHexParsingWithoutHash() {
        XCTAssertEqual(RGBAColor.hex("00FF00").g, 1.0, accuracy: 0.001)
    }

    func testHexParsingEightDigitsAlpha() {
        let c = RGBAColor.hex("#FFFFFF80")
        XCTAssertEqual(c.a, 128.0 / 255.0, accuracy: 0.001)
    }

    func testHexParsingInvalidIsBlack() {
        let c = RGBAColor.hex("zzz")
        XCTAssertEqual(c.r, 0)
        XCTAssertEqual(c.g, 0)
        XCTAssertEqual(c.b, 0)
    }

    func testResolvedColorsClampToSix() {
        let config = GradientConfig(colors: Array(repeating: RGBAColor(r: 1, g: 0, b: 0), count: 9))
        XCTAssertEqual(config.resolvedColors.count, 6)
    }

    func testResolvedColorsPadToTwoMinimum() {
        let config = GradientConfig(colors: [RGBAColor(r: 1, g: 1, b: 1)])
        XCTAssertEqual(config.resolvedColors.count, 2)
    }

    func testCodableRoundTrip() throws {
        let original = GradientPresets.default.config
        let data = try JSONStore.encoder.encode(original)
        let decoded = try JSONStore.decoder.decode(GradientConfig.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testPresetsAreUnique() {
        let ids = GradientPresets.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertFalse(GradientPresets.all.isEmpty)
    }

    func testStyleShaderIndicesAreDistinct() {
        let indices = GradientStyle.allCases.map(\.shaderIndex)
        XCTAssertEqual(Set(indices).count, GradientStyle.allCases.count)
    }
}
