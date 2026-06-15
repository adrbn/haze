import Foundation
import simd

/// A normalised RGBA colour (components in 0...1) that survives JSON round-trips
/// and converts cheaply to the `SIMD4<Float>` the Metal shader consumes.
public struct RGBAColor: Codable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public var simd: SIMD4<Float> {
        SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
    }

    /// Parses `#RRGGBB` / `RRGGBB` / `#RRGGBBAA`. Invalid input → opaque black.
    public static func hex(_ string: String) -> RGBAColor {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let value = UInt64(s, radix: 16) else { return RGBAColor(r: 0, g: 0, b: 0) }
        switch s.count {
        case 6:
            return RGBAColor(
                r: Double((value >> 16) & 0xFF) / 255,
                g: Double((value >> 8) & 0xFF) / 255,
                b: Double(value & 0xFF) / 255)
        case 8:
            return RGBAColor(
                r: Double((value >> 24) & 0xFF) / 255,
                g: Double((value >> 16) & 0xFF) / 255,
                b: Double((value >> 8) & 0xFF) / 255,
                a: Double(value & 0xFF) / 255)
        default:
            return RGBAColor(r: 0, g: 0, b: 0)
        }
    }
}

/// Visual flavour of the generated gradient field.
public enum GradientStyle: String, Codable, Sendable, CaseIterable {
    case aurora    // soft flowing bands (shadergradient "plane")
    case liquid    // heavier domain warp (shadergradient "waterPlane")
    case halo      // radial bloom from a moving centre (shadergradient "sphere")

    public var displayName: String {
        switch self {
        case .aurora: return "Aurora"
        case .liquid: return "Liquid"
        case .halo: return "Halo"
        }
    }
}

/// Everything needed to render an animated 2D gradient field. Fully Codable so
/// gradient items can be persisted in the library and shared.
public struct GradientConfig: Codable, Hashable, Sendable {
    public var colors: [RGBAColor]   // 2...6 used; extras ignored by the shader
    public var speed: Double         // 0...2, animation rate
    public var grain: Double         // 0...1, film grain amount
    public var warp: Double          // 0...2, domain-warp intensity
    public var brightness: Double    // 0.5...1.5
    public var blur: Double          // 0 = sharp; gaussian softening
    public var style: GradientStyle
    public var fps: Int              // preferred render rate

    public init(colors: [RGBAColor],
                speed: Double = 0.5,
                grain: Double = 0.12,
                warp: Double = 1.0,
                brightness: Double = 1.0,
                blur: Double = 0.0,
                style: GradientStyle = .aurora,
                fps: Int = 30) {
        self.colors = colors
        self.speed = speed
        self.grain = grain
        self.warp = warp
        self.brightness = brightness
        self.blur = blur
        self.style = style
        self.fps = fps
    }

    enum CodingKeys: String, CodingKey {
        case colors, speed, grain, warp, brightness, blur, style, fps
    }

    /// Tolerant decode so 2D gradients saved before `blur` existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GradientConfig(colors: [RGBAColor(r: 0, g: 0, b: 0), RGBAColor(r: 1, g: 1, b: 1)])
        colors = (try? c.decode([RGBAColor].self, forKey: .colors)) ?? d.colors
        speed = (try? c.decode(Double.self, forKey: .speed)) ?? d.speed
        grain = (try? c.decode(Double.self, forKey: .grain)) ?? d.grain
        warp = (try? c.decode(Double.self, forKey: .warp)) ?? d.warp
        brightness = (try? c.decode(Double.self, forKey: .brightness)) ?? d.brightness
        blur = (try? c.decode(Double.self, forKey: .blur)) ?? d.blur
        style = (try? c.decode(GradientStyle.self, forKey: .style)) ?? .aurora
        fps = (try? c.decode(Int.self, forKey: .fps)) ?? d.fps
    }

    /// Clamped, shader-ready colours (always 2...6 entries).
    public var resolvedColors: [SIMD4<Float>] {
        let trimmed = Array(colors.prefix(6))
        let padded = trimmed.count >= 2 ? trimmed : (trimmed + Array(repeating: RGBAColor(r: 0, g: 0, b: 0), count: 2 - trimmed.count))
        return padded.map(\.simd)
    }
}
