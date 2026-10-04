import XCTest
@testable import HazeKit

/// The poster is one frozen frame of the wallpaper, and it is what macOS shows
/// behind the lock screen. Picking that frame needs a score that tells a *hard*
/// edge — a polygon silhouette cut by the depth buffer where the displaced
/// surface folds over itself — apart from a merely steep gradient.
final class StillFrameTests: XCTestCase {
    private let side = 64

    /// BGRA, opaque, built from a luma function.
    private func image(_ value: (Int, Int) -> UInt8) -> [UInt8] {
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let v = value(x, y)
                let i = (y * side + x) * 4
                bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v
            }
        }
        return bytes
    }

    private func score(_ bytes: [UInt8]) -> Float {
        StillFrame.discontinuity(bgra: bytes, width: side, height: side)
    }

    func testFlatImageHasNoDiscontinuity() {
        XCTAssertEqual(score(image { _, _ in 128 }), 0, accuracy: 0.001)
    }

    /// The whole point: the gradients being scored are steep by design. Slope
    /// alone must not read as a defect, or every frame scores the same and the
    /// choice is arbitrary.
    func testSteepSmoothRampHasNoDiscontinuity() {
        let ramp = image { x, _ in UInt8(x * 255 / (self.side - 1)) }
        XCTAssertLessThan(score(ramp), 1)
    }

    func testHardEdgeScoresFarAboveASmoothRamp() {
        let ramp = image { x, _ in UInt8(x * 255 / (self.side - 1)) }
        let step = image { x, _ in x < self.side / 2 ? 40 : 210 }
        XCTAssertGreaterThan(score(step), 20 * score(ramp))
        XCTAssertGreaterThan(score(step), 50)
    }

    /// Film grain is on in every preset (0.44). The score has to see through it,
    /// otherwise noise drowns the signal it is looking for.
    func testFilmGrainScoresFarBelowAHardEdge() {
        var seed: UInt64 = 0x9E3779B9
        func noise() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(seed >> 33) % 19 - 9          // ±9, the grain's amplitude
        }
        let grainy = image { _, _ in UInt8(clamping: 128 + noise()) }
        let step = image { x, _ in x < self.side / 2 ? 40 : 210 }
        XCTAssertLessThan(score(grainy), score(step) / 3)
    }

    func testEmptyInputIsRejected() {
        XCTAssertEqual(StillFrame.discontinuity(bgra: [], width: 0, height: 0), 0)
    }
}
