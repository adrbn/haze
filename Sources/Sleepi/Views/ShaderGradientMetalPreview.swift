import SwiftUI
import AppKit
import SleepiKit

/// Live, animated 3D ShaderGradient preview. Driven by a timer (externally
/// driven) so it renders reliably inside a sheet, where MTKView's own display
/// link does not always fire.
struct ShaderGradientMetalPreview: NSViewRepresentable {
    let config: ShaderGradientConfig

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        if let renderer = ShaderGradientRenderer(config: config) {
            context.coordinator.renderer = renderer
            let view = renderer.view
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            renderer.setExternallyDriven(true)
            renderer.start()
            context.coordinator.startTimer(fps: config.fps)
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.renderer?.update(config: config)
        context.coordinator.startTimer(fps: config.fps)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: ShaderGradientRenderer?
        private var timer: Timer?
        private var fps = 0

        func startTimer(fps requested: Int) {
            let clamped = min(max(requested > 0 ? requested : 30, 1), 60)
            if timer != nil, clamped == fps { return }
            fps = clamped
            timer?.invalidate()
            let t = Timer(timeInterval: 1.0 / Double(clamped), repeats: true) { [weak self] _ in
                self?.renderer?.tick()
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }

        func stop() {
            timer?.invalidate(); timer = nil
            renderer?.stop(); renderer = nil
        }
    }
}
