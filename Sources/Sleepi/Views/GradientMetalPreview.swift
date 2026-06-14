import SwiftUI
import AppKit
import SleepiKit

/// Live, animated Metal gradient preview that updates as the config changes.
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
            renderer.start()
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.renderer?.update(config: config)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: GradientRenderer?
    }
}
