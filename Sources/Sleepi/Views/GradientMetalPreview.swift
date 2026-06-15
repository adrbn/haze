import SwiftUI
import AppKit
import SleepiKit

/// Live, animated 2D gradient preview. Timer-driven (externally driven) so it
/// renders reliably inside a sheet.
struct GradientMetalPreview: NSViewRepresentable {
    let config: GradientConfig

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        if let renderer = GradientRenderer(config: config) {
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
            context.coordinator.startTimer()
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.renderer?.update(config: config)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: GradientRenderer?
        private var timer: Timer?

        func startTimer() {
            timer?.invalidate()
            let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
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
