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
        ContentItem.shaderGradient(config, name: name, author: "Haze")
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
        ShaderGradientPreset(
            id: "iris3d", name: "Iris",
            config: ShaderGradientConfig(colors: [.hex("#7B2FF7"), .hex("#3A86FF"), .hex("#0A1033")],
                type: .plane, speed: 0.35, density: 1.4, frequency: 5.0, amplitude: 1.0, strength: 3.4,
                brightness: 1.05, grain: 0.9, reflection: 0.12, rotationZ: 50, fps: 30)),
        ShaderGradientPreset(
            id: "coral3d", name: "Coral",
            config: ShaderGradientConfig(colors: [.hex("#FF6B6B"), .hex("#FF9E7D"), .hex("#FFD6A5")],
                type: .plane, speed: 0.32, density: 1.3, frequency: 5.0, amplitude: 1.0, strength: 3.0,
                brightness: 1.08, grain: 0.8, reflection: 0.1, rotationZ: 45, fps: 30)),
        ShaderGradientPreset(
            id: "mint3d", name: "Mint",
            config: ShaderGradientConfig(colors: [.hex("#22E0A1"), .hex("#1BC7C7"), .hex("#0B5E5E")],
                type: .waterPlane, speed: 0.4, density: 1.3, frequency: 6.0, amplitude: 1.3, strength: 3.0,
                brightness: 1.05, grain: 0.8, reflection: 0.16, rotationZ: 35, fps: 30)),
        ShaderGradientPreset(
            id: "plum3d", name: "Plum",
            config: ShaderGradientConfig(colors: [.hex("#2A0A4A"), .hex("#A8327D"), .hex("#FF6EC7")],
                type: .plane, speed: 0.33, density: 1.5, frequency: 5.0, amplitude: 1.0, strength: 3.6,
                brightness: 1.0, grain: 1.0, reflection: 0.12, rotationZ: 55, fps: 30)),
        ShaderGradientPreset(
            id: "gold3d", name: "Gold",
            config: ShaderGradientConfig(colors: [.hex("#FFC83D"), .hex("#FF8A00"), .hex("#5A2B00")],
                type: .plane, speed: 0.34, density: 1.35, frequency: 5.0, amplitude: 1.0, strength: 3.2,
                brightness: 1.06, grain: 0.9, reflection: 0.12, rotationZ: 48, fps: 30)),
        ShaderGradientPreset(
            id: "sky3d", name: "Sky",
            config: ShaderGradientConfig(colors: [.hex("#56CCF2"), .hex("#A0E9FF"), .hex("#E8F7FF")],
                type: .plane, speed: 0.3, density: 1.3, frequency: 5.0, amplitude: 1.0, strength: 2.6,
                brightness: 1.1, grain: 0.6, reflection: 0.1, rotationZ: 40, fps: 30)),
        ShaderGradientPreset(
            id: "ocean3d", name: "Ocean",
            config: ShaderGradientConfig(colors: [.hex("#0077B6"), .hex("#00B4D8"), .hex("#03045E")],
                type: .waterPlane, speed: 0.4, density: 1.4, frequency: 6.5, amplitude: 1.5, strength: 3.2,
                brightness: 1.0, grain: 0.8, reflection: 0.2, rotationZ: 30, fps: 30)),
        ShaderGradientPreset(
            id: "rose3d", name: "Rose",
            config: ShaderGradientConfig(colors: [.hex("#FF8FB1"), .hex("#FFC2D1"), .hex("#FFE5EC")],
                type: .plane, speed: 0.28, density: 1.3, frequency: 5.0, amplitude: 1.0, strength: 2.6,
                brightness: 1.1, grain: 0.6, reflection: 0.08, rotationZ: 52, fps: 30)),
        ShaderGradientPreset(
            id: "cosmic3d", name: "Cosmic",
            config: ShaderGradientConfig(colors: [.hex("#3A0CA3"), .hex("#7209B7"), .hex("#03010F")],
                type: .sphere, speed: 0.42, density: 1.5, frequency: 5.5, amplitude: 1.0, strength: 4.0,
                brightness: 1.0, grain: 1.0, reflection: 0.15, rotationZ: 40, fps: 30)),
        ShaderGradientPreset(
            id: "lava3d", name: "Lava",
            config: ShaderGradientConfig(colors: [.hex("#FF1E00"), .hex("#FF7A00"), .hex("#1A0300")],
                type: .waterPlane, speed: 0.5, density: 1.6, frequency: 7.5, amplitude: 1.5, strength: 4.2,
                brightness: 1.05, grain: 1.0, reflection: 0.1, rotationZ: 42, fps: 30)),
        ShaderGradientPreset(
            id: "peach3d", name: "Peach",
            config: ShaderGradientConfig(colors: [.hex("#FFB997"), .hex("#FFD6BA"), .hex("#F7B2C4")],
                type: .plane, speed: 0.3, density: 1.3, frequency: 5.0, amplitude: 1.0, strength: 2.8,
                brightness: 1.08, grain: 0.7, reflection: 0.1, rotationZ: 50, fps: 30)),
        ShaderGradientPreset(
            id: "steel3d", name: "Steel",
            config: ShaderGradientConfig(colors: [.hex("#8095A8"), .hex("#B7C4CF"), .hex("#2B3A45")],
                type: .plane, speed: 0.3, density: 1.4, frequency: 5.0, amplitude: 1.0, strength: 3.0,
                brightness: 1.0, grain: 1.0, reflection: 0.18, rotationZ: 46, fps: 30)),
        ShaderGradientPreset(
            id: "neon3d", name: "Neon",
            config: ShaderGradientConfig(colors: [.hex("#00F5D4"), .hex("#F15BB5"), .hex("#9B5DE5")],
                type: .plane, speed: 0.45, density: 1.5, frequency: 5.5, amplitude: 1.0, strength: 3.6,
                brightness: 1.08, grain: 0.9, reflection: 0.14, rotationZ: 55, fps: 30)),
        ShaderGradientPreset(
            id: "ember3d", name: "Ember 3D",
            config: ShaderGradientConfig(colors: [.hex("#3A0A00"), .hex("#FF6B00"), .hex("#FFD08A")],
                type: .plane, speed: 0.36, density: 1.4, frequency: 5.0, amplitude: 1.0, strength: 3.4,
                brightness: 1.05, grain: 1.0, reflection: 0.1, rotationZ: 44, fps: 30)),
    ]

    public static var `default`: ShaderGradientPreset { all[0] }

    public static func preset(id: String) -> ShaderGradientPreset? {
        all.first { $0.id == id }
    }
}
