import XCTest
@testable import SleepiKit

final class ShaderGradientConfigTests: XCTestCase {
    func testHalo3DMatchesReferenceProps() {
        let c = ShaderGradientPresets.preset(id: "halo3d")!.config
        XCTAssertEqual(c.type, .plane)
        XCTAssertEqual(c.colors.first, RGBAColor.hex("#ff5005"))
        XCTAssertEqual(c.colors.count, 3)
        XCTAssertEqual(c.speed, 0.4, accuracy: 0.001)
        XCTAssertEqual(c.density, 1.3, accuracy: 0.001)
        XCTAssertEqual(c.frequency, 5.5, accuracy: 0.001)
        XCTAssertEqual(c.amplitude, 1.0, accuracy: 0.001)
        XCTAssertEqual(c.strength, 4.0, accuracy: 0.001)
        XCTAssertEqual(c.brightness, 1.2, accuracy: 0.001)
        XCTAssertEqual(c.cPolarAngle, 90, accuracy: 0.001)
        XCTAssertEqual(c.cAzimuthAngle, 180, accuracy: 0.001)
        XCTAssertEqual(c.cDistance, 3.6, accuracy: 0.001)
        XCTAssertEqual(c.fov, 45, accuracy: 0.001)
        XCTAssertEqual(c.positionX, -1.4, accuracy: 0.001)
        XCTAssertEqual(c.rotationY, 10, accuracy: 0.001)
        XCTAssertEqual(c.rotationZ, 50, accuracy: 0.001)
    }

    func testResolvedColorsAlwaysThree() {
        let c = ShaderGradientConfig(colors: [.hex("#ff0000")])
        XCTAssertEqual(c.resolvedColors.count, 3)
        let many = ShaderGradientConfig(colors: Array(repeating: .hex("#00ff00"), count: 7))
        XCTAssertEqual(many.resolvedColors.count, 3)
    }

    func testCodableRoundTrip() throws {
        let original = ShaderGradientPresets.default.config
        let data = try JSONStore.encoder.encode(original)
        let decoded = try JSONStore.decoder.decode(ShaderGradientConfig.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testTolerantDecodeFillsDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONStore.decoder.decode(ShaderGradientConfig.self, from: json)
        XCTAssertEqual(decoded.type, .plane)
        XCTAssertEqual(decoded.cDistance, 3.6, accuracy: 0.001)
        XCTAssertEqual(decoded.colors.count, 3)
    }

    func testPresetsUnique() {
        let ids = ShaderGradientPresets.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertFalse(ShaderGradientPresets.all.isEmpty)
    }

    func testTypeShaderIndicesDistinct() {
        let idx = GradientType.allCases.map(\.shaderIndex)
        XCTAssertEqual(Set(idx).count, GradientType.allCases.count)
    }

    func testItemHelperSetsType() {
        let item = ContentItem.shaderGradient(ShaderGradientPresets.default.config, name: "X")
        XCTAssertEqual(item.type, .shaderGradient)
        XCTAssertNotNil(item.shaderGradient)
        XCTAssertTrue(item.type.isGradient)
    }
}
