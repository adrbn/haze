import Foundation

/// A named, ready-to-use 3D ShaderGradient configuration.
public struct ShaderGradientPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let config: ShaderGradientConfig

    public init(id: String, name: String, config: ShaderGradientConfig) {
        self.id = id
        self.name = name
        self.config = config
    }

    public func makeItem() -> ContentItem {
        ContentItem.shaderGradient(config, name: name, author: "Sleepi")
    }
}

/// Curated 3D presets. "Halo 3D" reproduces the exact `<ShaderGradient>` props
/// from the reference (orange → tan → lilac plane, oblique camera, 50° roll).
public enum ShaderGradientPresets {
    public static let all: [ShaderGradientPreset] = [
        ShaderGradientPreset(
            id: "halo3d",
            name: "Halo 3D",
            config: ShaderGradientConfig(
                colors: [.hex("#ff5005"), .hex("#dbba95"), .hex("#d0bce1")],
                type: .plane,
                speed: 0.4, density: 1.3, frequency: 5.5, amplitude: 1.0, strength: 4.0,
                brightness: 1.2, grain: 1.0, reflection: 0.1,
                cPolarAngle: 90, cAzimuthAngle: 180, cDistance: 3.6, fov: 45,
                positionX: -1.4, positionY: 0, positionZ: 0,
                rotationX: 0, rotationY: 10, rotationZ: 50, fps: 30)),
        ShaderGradientPreset(
            id: "dusk3d",
            name: "Dusk",
            config: ShaderGradientConfig(
                colors: [.hex("#1E2A78"), .hex("#A8327D"), .hex("#FFB36B")],
                type: .plane,
                speed: 0.35, density: 1.5, frequency: 5.0, amplitude: 1.0, strength: 3.4,
                brightness: 1.15, grain: 1.0, reflection: 0.12,
                cPolarAngle: 90, cAzimuthAngle: 180, cDistance: 3.8, fov: 45,
                positionX: -1.0, positionY: 0, positionZ: 0,
                rotationX: 0, rotationY: 10, rotationZ: 40, fps: 30)),
        ShaderGradientPreset(
            id: "tide3d",
            name: "Tide",
            config: ShaderGradientConfig(
                colors: [.hex("#00E0C7"), .hex("#1E7BFF"), .hex("#0A1E5E")],
                type: .waterPlane,
                speed: 0.5, density: 1.2, frequency: 6.5, amplitude: 1.6, strength: 3.0,
                brightness: 1.1, grain: 1.0, reflection: 0.18,
                cPolarAngle: 90, cAzimuthAngle: 180, cDistance: 3.6, fov: 45,
                positionX: 0, positionY: 0, positionZ: 0,
                rotationX: 0, rotationY: 8, rotationZ: 35, fps: 30)),
        ShaderGradientPreset(
            id: "blush3d",
            name: "Blush",
            config: ShaderGradientConfig(
                colors: [.hex("#FFD6E8"), .hex("#C9B6FF"), .hex("#8AD7FF")],
                type: .plane,
                speed: 0.3, density: 1.4, frequency: 5.0, amplitude: 1.0, strength: 2.8,
                brightness: 1.25, grain: 0.8, reflection: 0.08,
                cPolarAngle: 90, cAzimuthAngle: 180, cDistance: 3.6, fov: 45,
                positionX: -1.2, positionY: 0, positionZ: 0,
                rotationX: 0, rotationY: 12, rotationZ: 55, fps: 30)),
        ShaderGradientPreset(
            id: "magma3d",
            name: "Magma",
            config: ShaderGradientConfig(
                colors: [.hex("#FF2D00"), .hex("#FF8A00"), .hex("#2B0700")],
                type: .waterPlane,
                speed: 0.55, density: 1.6, frequency: 7.0, amplitude: 1.4, strength: 4.2,
                brightness: 1.1, grain: 1.0, reflection: 0.1,
                cPolarAngle: 90, cAzimuthAngle: 180, cDistance: 3.4, fov: 45,
                positionX: -0.8, positionY: 0, positionZ: 0,
                rotationX: 0, rotationY: 10, rotationZ: 45, fps: 30)),
    ]

    public static var `default`: ShaderGradientPreset { all[0] }

    public static func preset(id: String) -> ShaderGradientPreset? {
        all.first { $0.id == id }
    }
}
