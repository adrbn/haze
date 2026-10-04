import XCTest
import CoreGraphics
import Metal
@testable import HazeKit

/// The poster macOS uses as the desktop picture has to be a real render of the
/// wallpaper. It drives the menu bar's light/dark treatment, so a stand-in that
/// only approximates the colours can make macOS pick the wrong one.
final class GradientSnapshotTests: XCTestCase {
    private let size = CGSize(width: 160, height: 100)

    private let colors = [
        RGBAColor(r: 0.227, g: 0.047, b: 0.639),
        RGBAColor(r: 0.447, g: 0.035, b: 0.718),
        RGBAColor(r: 0.012, g: 0.004, b: 0.059),
    ]

    override func setUpWithError() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal device")
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = try XCTUnwrap(CGContext(data: &bytes, width: w, height: h,
                                          bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space, bitmapInfo: info))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bytes
    }

    // MARK: Shader gradient

    func testShaderSnapshotHasRequestedSize() throws {
        let image = try XCTUnwrap(GradientSnapshot.image(
            config: ShaderGradientConfig(colors: colors, type: .sphere), size: size))
        XCTAssertEqual(image.width, Int(size.width))
        XCTAssertEqual(image.height, Int(size.height))
    }

    /// Posters are cached by a hash of their config, so the same config must
    /// always produce the same image (grain included — it is seeded from the
    /// frame time, which is pinned at 0 for a still).
    func testShaderSnapshotIsDeterministic() throws {
        let config = ShaderGradientConfig(colors: colors, type: .sphere)
        let a = try pixels(try XCTUnwrap(GradientSnapshot.image(config: config, size: size)))
        let b = try pixels(try XCTUnwrap(GradientSnapshot.image(config: config, size: size)))
        XCTAssertEqual(a, b)
    }

    /// The regression: the old poster was an `NSGradient` diagonal sweep built from
    /// the colours alone, so every camera/rotation/shape change produced a byte-identical
    /// file. A real render must react to them.
    func testShaderSnapshotReflectsNonColourParameters() throws {
        let straight = ShaderGradientConfig(colors: colors, type: .sphere, rotationZ: 0)
        let rolled = ShaderGradientConfig(colors: colors, type: .sphere, rotationZ: 50)
        let a = try pixels(try XCTUnwrap(GradientSnapshot.image(config: straight, size: size)))
        let b = try pixels(try XCTUnwrap(GradientSnapshot.image(config: rolled, size: size)))
        XCTAssertNotEqual(a, b)
    }

    /// The surface type has to reach the shader. Only `waterPlane` currently
    /// displaces differently (`sg_displace` branches on it alone — `plane` and
    /// `sphere` deliberately share a displacement today), so that is the pair
    /// that proves the uniform is wired through.
    func testShaderSnapshotReflectsSurfaceType() throws {
        let plane = ShaderGradientConfig(colors: colors, type: .plane)
        let water = ShaderGradientConfig(colors: colors, type: .waterPlane)
        let a = try pixels(try XCTUnwrap(GradientSnapshot.image(config: plane, size: size)))
        let b = try pixels(try XCTUnwrap(GradientSnapshot.image(config: water, size: size)))
        XCTAssertNotEqual(a, b)
    }

    /// BGRA, the layout `StillFrame` scores and the one Metal renders into.
    private func bgra(_ image: CGImage) throws -> [UInt8] {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let ctx = try XCTUnwrap(CGContext(data: &bytes, width: w, height: h,
                                          bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: info))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bytes
    }

    /// The regression this guards: the poster was frozen at t = 0, and at t = 0
    /// every preset's displaced surface has a fold whose silhouette lands near
    /// the middle of the frame. A frozen silhouette is a hard, aliased edge in
    /// an otherwise smooth image — and macOS shows the poster full-screen, with
    /// nothing on top of it, behind the lock screen.
    ///
    /// Scored with the grain off: it is noise to this measurement, and on a
    /// 2.6–4.2 `strength` surface the fold is a property of the geometry, not of
    /// the grain. The shipped presets keep their own grain.
    func testChosenStillIsFarSmootherThanFrameZeroForEveryPreset() throws {
        let size = CGSize(width: 640, height: 400)
        for preset in ShaderGradientPresets.all {
            var config = preset.config
            config.grain = 0
            let chosen = try XCTUnwrap(GradientSnapshot.image(config: config, size: size))
            let frameZero = try XCTUnwrap(GradientSnapshot.image(config: config, size: size, time: 0))
            let edge = StillFrame.discontinuity(bgra: try bgra(chosen),
                                                width: Int(size.width), height: Int(size.height))
            let edgeAtZero = StillFrame.discontinuity(bgra: try bgra(frameZero),
                                                      width: Int(size.width), height: Int(size.height))
            XCTAssertLessThan(edge, edgeAtZero / 3,
                              "\(preset.name): still has a hard edge (\(edge) vs \(edgeAtZero) at t=0)")
        }
    }

    /// Callers that pin a frame must still get exactly that frame — the chooser
    /// only fills in for the default.
    func testExplicitTimePinsTheFrame() throws {
        let config = ShaderGradientConfig(colors: colors, type: .sphere)
        let a = try pixels(try XCTUnwrap(GradientSnapshot.image(config: config, size: size, time: 0)))
        let b = try pixels(try XCTUnwrap(GradientSnapshot.image(config: config, size: size, time: 0.9)))
        XCTAssertNotEqual(a, b)
    }

    /// Posters are cached under a filename built from this. It has to move when
    /// the renderer changes what a config draws, or an upgrade leaves the old
    /// image sitting under the name macOS has already been given.
    func testSignatureCarriesTheRendererRevision() {
        let config = ShaderGradientConfig(colors: colors, type: .sphere)
        XCTAssertTrue(GradientSnapshot.signature(of: config).hasPrefix("r\(GradientSnapshot.revision)|"))
        XCTAssertNotEqual(GradientSnapshot.signature(of: config), ContentSignature.of(config))
    }

    func testShaderSnapshotSurvivesBlur() throws {
        let config = ShaderGradientConfig(colors: colors, type: .sphere, blur: 0.3)
        let image = try XCTUnwrap(GradientSnapshot.image(config: config, size: size))
        XCTAssertEqual(image.width, Int(size.width))
    }

    func testShaderSnapshotIsOpaque() throws {
        let image = try XCTUnwrap(GradientSnapshot.image(
            config: ShaderGradientConfig(colors: colors, type: .sphere), size: size))
        let bytes = try pixels(image)
        let alphas = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
        XCTAssertTrue(alphas.allSatisfy { $0 == 255 }, "a desktop picture must be fully opaque")
    }

    // MARK: 2D gradient

    func testGradientSnapshotHasRequestedSize() throws {
        let image = try XCTUnwrap(GradientSnapshot.image(
            config: GradientConfig(colors: colors), size: size))
        XCTAssertEqual(image.width, Int(size.width))
        XCTAssertEqual(image.height, Int(size.height))
    }

    func testGradientSnapshotReflectsStyle() throws {
        let aurora = GradientConfig(colors: colors, style: .aurora)
        let halo = GradientConfig(colors: colors, style: .halo)
        let a = try pixels(try XCTUnwrap(GradientSnapshot.image(config: aurora, size: size)))
        let b = try pixels(try XCTUnwrap(GradientSnapshot.image(config: halo, size: size)))
        XCTAssertNotEqual(a, b)
    }

    func testZeroSizeIsRejected() {
        XCTAssertNil(GradientSnapshot.image(config: ShaderGradientConfig(colors: colors), size: .zero))
    }
}
