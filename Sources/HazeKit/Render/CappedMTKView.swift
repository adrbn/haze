import MetalKit

/// An `MTKView` that caps its drawable's longest side. A smooth gradient doesn't
/// need full 4K/5K fragment shading — rendering at ≤1920 and letting the layer
/// scale up is imperceptible but cuts GPU work (and heat) ~4× on a 4K display.
/// This is what kept the gradient *screensaver* pinning a base M1 at ~44% / 79°C.
final class CappedMTKView: MTKView {
    var maxDrawableDimension: CGFloat = 1920 {
        didSet { updateDrawableSize() }
    }

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        autoResizeDrawable = false   // we size the drawable ourselves (capped)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? layer?.contentsScale ?? 2
        var w = bounds.width * scale
        var h = bounds.height * scale
        guard w > 1, h > 1 else { return }
        let longest = max(w, h)
        if longest > maxDrawableDimension {
            let f = maxDrawableDimension / longest
            w *= f; h *= f
        }
        let size = CGSize(width: w.rounded(), height: h.rounded())
        if drawableSize != size { drawableSize = size }
    }
}
