import Foundation
import simd

/// Surface type, matching shadergradient.co.
public enum GradientType: String, Codable, Sendable, CaseIterable {
    case plane
    case waterPlane
    case sphere

    public var displayName: String {
        switch self {
        case .plane: return "Plane"
        case .waterPlane: return "Water"
        case .sphere: return "Sphere"
        }
    }

    var shaderIndex: Int32 {
        switch self {
        case .plane: return 0
        case .waterPlane: return 1
        case .sphere: return 2
        }
    }
}

/// A shadergradient.co-style gradient: a noise-displaced, lit 3D surface coloured
/// with three stops and viewed through a configurable camera. Field names mirror
/// the `<ShaderGradient>` props (`uSpeed`, `uDensity`, …). This is additive — the
/// classic 2D `GradientConfig` still exists for the Aurora/Liquid/Halo fields.
public struct ShaderGradientConfig: Codable, Hashable, Sendable {
    public var colors: [RGBAColor]   // color1, color2, color3
    public var type: GradientType

    // Noise / animation (the `u*` props)
    public var speed: Double         // uSpeed
    public var density: Double       // uDensity
    public var frequency: Double     // uFrequency
    public var amplitude: Double     // uAmplitude
    public var strength: Double      // uStrength

    // Look
    public var brightness: Double
    public var grain: Double         // 0 = off
    public var blur: Double          // 0 = sharp; gaussian softening
    public var reflection: Double

    // Camera (spherical) + lens
    public var cPolarAngle: Double
    public var cAzimuthAngle: Double
    public var cDistance: Double
    public var fov: Double

    // Object transform (degrees / world units)
    public var positionX: Double
    public var positionY: Double
    public var positionZ: Double
    public var rotationX: Double
    public var rotationY: Double
    public var rotationZ: Double

    public var fps: Int

    public init(colors: [RGBAColor],
                type: GradientType = .plane,
                speed: Double = 0.4,
                density: Double = 1.3,
                frequency: Double = 5.5,
                amplitude: Double = 1.0,
                strength: Double = 4.0,
                brightness: Double = 1.2,
                grain: Double = 1.0,
                blur: Double = 0.0,
                reflection: Double = 0.1,
                cPolarAngle: Double = 90,
                cAzimuthAngle: Double = 180,
                cDistance: Double = 3.6,
                fov: Double = 45,
                positionX: Double = -1.4,
                positionY: Double = 0,
                positionZ: Double = 0,
                rotationX: Double = 0,
                rotationY: Double = 10,
                rotationZ: Double = 50,
                fps: Int = 30) {
        self.colors = colors
        self.type = type
        self.speed = speed
        self.density = density
        self.frequency = frequency
        self.amplitude = amplitude
        self.strength = strength
        self.brightness = brightness
        self.grain = grain
        self.blur = blur
        self.reflection = reflection
        self.cPolarAngle = cPolarAngle
        self.cAzimuthAngle = cAzimuthAngle
        self.cDistance = cDistance
        self.fov = fov
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.rotationZ = rotationZ
        self.fps = fps
    }

    /// Three shader-ready colours (always exactly 3 entries).
    public var resolvedColors: [SIMD4<Float>] {
        var cs = Array(colors.prefix(3))
        while cs.count < 3 { cs.append(cs.last ?? RGBAColor(r: 0, g: 0, b: 0)) }
        return cs.map(\.simd)
    }

    enum CodingKeys: String, CodingKey {
        case colors, type, speed, density, frequency, amplitude, strength
        case brightness, grain, blur, reflection
        case cPolarAngle, cAzimuthAngle, cDistance, fov
        case positionX, positionY, positionZ, rotationX, rotationY, rotationZ, fps
    }

    /// Tolerant decode so future field additions don't break old saves.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ShaderGradientConfig(colors: [.hex("#ff5005"), .hex("#dbba95"), .hex("#d0bce1")])
        colors = (try? c.decode([RGBAColor].self, forKey: .colors)) ?? d.colors
        type = (try? c.decode(GradientType.self, forKey: .type)) ?? .plane
        speed = (try? c.decode(Double.self, forKey: .speed)) ?? d.speed
        density = (try? c.decode(Double.self, forKey: .density)) ?? d.density
        frequency = (try? c.decode(Double.self, forKey: .frequency)) ?? d.frequency
        amplitude = (try? c.decode(Double.self, forKey: .amplitude)) ?? d.amplitude
        strength = (try? c.decode(Double.self, forKey: .strength)) ?? d.strength
        brightness = (try? c.decode(Double.self, forKey: .brightness)) ?? d.brightness
        grain = (try? c.decode(Double.self, forKey: .grain)) ?? d.grain
        blur = (try? c.decode(Double.self, forKey: .blur)) ?? d.blur
        reflection = (try? c.decode(Double.self, forKey: .reflection)) ?? d.reflection
        cPolarAngle = (try? c.decode(Double.self, forKey: .cPolarAngle)) ?? d.cPolarAngle
        cAzimuthAngle = (try? c.decode(Double.self, forKey: .cAzimuthAngle)) ?? d.cAzimuthAngle
        cDistance = (try? c.decode(Double.self, forKey: .cDistance)) ?? d.cDistance
        fov = (try? c.decode(Double.self, forKey: .fov)) ?? d.fov
        positionX = (try? c.decode(Double.self, forKey: .positionX)) ?? d.positionX
        positionY = (try? c.decode(Double.self, forKey: .positionY)) ?? d.positionY
        positionZ = (try? c.decode(Double.self, forKey: .positionZ)) ?? d.positionZ
        rotationX = (try? c.decode(Double.self, forKey: .rotationX)) ?? d.rotationX
        rotationY = (try? c.decode(Double.self, forKey: .rotationY)) ?? d.rotationY
        rotationZ = (try? c.decode(Double.self, forKey: .rotationZ)) ?? d.rotationZ
        fps = (try? c.decode(Int.self, forKey: .fps)) ?? d.fps
    }
}
