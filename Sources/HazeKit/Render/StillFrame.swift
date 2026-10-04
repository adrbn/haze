import Foundation

/// Scores a rendered frame for the one defect that makes a *frozen* gradient
/// look broken: a hard polygon silhouette.
///
/// The shadergradient surface is a plane displaced by 3D noise. At the
/// amplitudes the presets use (`strength` 2.6–4.2) it folds over itself, and
/// where a fold's silhouette crosses the frame the depth buffer leaves a hard,
/// aliased edge. Live, that edge drifts with the animation and reads as motion.
/// Frozen into the desktop poster — which is also what macOS shows behind the
/// lock screen — it is the only sharp thing in an otherwise smooth image, and it
/// reads as a defect.
///
/// Used to pick *which* frame becomes the poster. See `GradientSnapshot`.
enum StillFrame {
    /// Candidate frames, in wallpaper seconds. `0` is included so the chosen
    /// still can never be worse than the frame the renderer starts on.
    static let candidates: [Float] = [0, 0.3, 0.6, 0.9, 1.2, 1.5]

    /// Resolution the candidates are rendered at while being scored. A fold's
    /// silhouette spans a good fraction of the screen, so it survives this
    /// happily, and six renders this size cost a few milliseconds.
    static let scoringSize = CGSize(width: 512, height: 320)

    /// How hard the sharpest edge in `bgra` is, on a 0–255 luma scale.
    ///
    /// Box-filters the luma by `block` to suppress film grain, then takes the
    /// Laplacian. A gradient stays near zero however *steep* it is — the second
    /// derivative of a ramp is flat — while a silhouette spikes. Comparing raw
    /// neighbours instead would just measure how colourful the gradient is.
    static func discontinuity(bgra: [UInt8], width: Int, height: Int, block: Int = 4) -> Float {
        let w = width / block, h = height / block
        guard w > 2, h > 2, bgra.count >= width * height * 4 else { return 0 }

        var mean = [Float](repeating: 0, count: w * h)
        let divisor = Float(block * block)
        for y in 0..<h {
            for x in 0..<w {
                var sum: Float = 0
                for j in 0..<block {
                    for i in 0..<block {
                        let p = ((y * block + j) * width + (x * block + i)) * 4
                        sum += Float(bgra[p]) * 0.114 + Float(bgra[p + 1]) * 0.587 + Float(bgra[p + 2]) * 0.299
                    }
                }
                mean[y * w + x] = sum / divisor
            }
        }

        var peak: Float = 0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let laplacian = abs(4 * mean[y * w + x]
                                    - mean[y * w + x - 1] - mean[y * w + x + 1]
                                    - mean[(y - 1) * w + x] - mean[(y + 1) * w + x])
                peak = max(peak, laplacian)
            }
        }
        return peak
    }
}
