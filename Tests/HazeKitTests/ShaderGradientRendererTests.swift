import AppKit
import XCTest
@testable import HazeKit

/// Draws real frames through both render paths (sharp → MSAA resolved into the
/// drawable; blurred → MSAA resolved into the blur input). Run with
/// TEST_RUNNER_MTL_DEBUG_LAYER=1 to have Metal validation abort on a bad pass.
final class ShaderGradientRendererTests: XCTestCase {
    @MainActor
    func testDrawsSharpAndBlurredFrames() throws {
        var config = ShaderGradientPresets.preset(id: "halo3d")!.config
        for blur in [0.0, 0.2] {
            config.blur = blur
            let renderer = try XCTUnwrap(ShaderGradientRenderer(config: config))
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 640, height: 400),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = renderer.view
            renderer.view.layoutSubtreeIfNeeded()
            renderer.start()
            for _ in 0..<3 { renderer.redraw() }
            renderer.stop()
            window.close()
        }
    }
}
