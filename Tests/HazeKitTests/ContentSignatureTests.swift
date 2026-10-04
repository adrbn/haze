import XCTest
@testable import HazeKit

/// Poster filenames carry a signature of the config that produced them, so macOS
/// is forced to re-read the file whenever the wallpaper actually changed. The
/// signature therefore has to be stable across launches and cover every field.
final class ContentSignatureTests: XCTestCase {
    private let colors = [
        RGBAColor(r: 0.2, g: 0.1, b: 0.6),
        RGBAColor(r: 0.4, g: 0.0, b: 0.7),
        RGBAColor(r: 0.0, g: 0.0, b: 0.1),
    ]

    func testHashIsStableForTheSameString() {
        XCTAssertEqual(ContentSignature.hash("hello"), ContentSignature.hash("hello"))
    }

    func testHashDiffersForDifferentStrings() {
        XCTAssertNotEqual(ContentSignature.hash("hello"), ContentSignature.hash("hellp"))
    }

    func testHashIsFilenameSafe() {
        let allowed = CharacterSet.alphanumerics
        let hash = ContentSignature.hash("/Users/someone/a file.jpg")
        XCTAssertFalse(hash.isEmpty)
        XCTAssertTrue(hash.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    func testIdenticalConfigsShareASignature() {
        let a = ShaderGradientConfig(colors: colors, type: .sphere)
        let b = ShaderGradientConfig(colors: colors, type: .sphere)
        XCTAssertEqual(ContentSignature.of(a), ContentSignature.of(b))
    }

    /// The bug this guards: the old signature was built from the colours alone, so
    /// editing the camera or the rotation reused the previous poster file.
    func testNonColourChangesChangeTheSignature() {
        let base = ShaderGradientConfig(colors: colors, type: .sphere)
        var rolled = base; rolled.rotationZ += 10
        var moved = base; moved.positionX += 0.5
        var reshaped = base; reshaped.type = .waterPlane
        var grainier = base; grainier.grain += 0.2

        for (name, changed) in [("rotationZ", rolled), ("positionX", moved),
                                ("type", reshaped), ("grain", grainier)] {
            XCTAssertNotEqual(ContentSignature.of(base), ContentSignature.of(changed),
                              "\(name) must change the poster signature")
        }
    }

    func testColourChangesChangeTheSignature() {
        let base = ShaderGradientConfig(colors: colors, type: .sphere)
        var recoloured = base
        recoloured.colors[0] = RGBAColor(r: 0.9, g: 0.9, b: 0.9)
        XCTAssertNotEqual(ContentSignature.of(base), ContentSignature.of(recoloured))
    }

    func testWorksForThe2DGradientToo() {
        let base = GradientConfig(colors: colors)
        var warped = base; warped.warp += 0.5
        XCTAssertEqual(ContentSignature.of(base), ContentSignature.of(GradientConfig(colors: colors)))
        XCTAssertNotEqual(ContentSignature.of(base), ContentSignature.of(warped))
    }
}
