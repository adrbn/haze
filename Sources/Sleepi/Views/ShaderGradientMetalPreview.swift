import SwiftUI
import AppKit
import SleepiKit

/// Live, animated 3D ShaderGradient preview. Self-driven (the MTKView's own
/// display link), the same path the desktop wallpaper uses — reliable inside a
/// SwiftUI sheet, unlike a run-loop timer.
struct ShaderGradientMetalPreview: NSViewRepresentable {
    let config: ShaderGradientConfig

    func makeNSView(context: Context) -> NSView {
        guard let renderer = ShaderGradientRenderer(config: config) else {
            let placeholder = NSView()
            placeholder.wantsLayer = true
            placeholder.layer?.backgroundColor = NSColor.black.cgColor
            return placeholder
        }
        context.coordinator.renderer = renderer
        renderer.start()
        return renderer.view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.renderer?.update(config: config)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.renderer?.stop()
        coordinator.renderer = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: ShaderGradientRenderer?
    }
}
