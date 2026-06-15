import Foundation

/// A named, ready-to-use gradient configuration.
public struct GradientPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let config: GradientConfig

    public init(id: String, name: String, config: GradientConfig) {
        self.id = id
        self.name = name
        self.config = config
    }

    /// Build a library item from this preset.
    public func makeItem() -> ContentItem {
        ContentItem.gradient(config, name: name, author: "Sleepi")
    }
}

/// Curated presets inspired by shadergradient.co. These ship in the app and
/// seed the gradient gallery on first launch.
public enum GradientPresets {
    public static let all: [GradientPreset] = [
        GradientPreset(
            id: "halo",
            name: "Halo",
            config: GradientConfig(
                colors: [.hex("#FF3B00"), .hex("#FF7A3D"), .hex("#C9A6FF"), .hex("#B07CFF")],
                speed: 0.45, grain: 0.06, warp: 1.1, brightness: 1.05, style: .halo, fps: 30)),
        GradientPreset(
            id: "aurora",
            name: "Aurora",
            config: GradientConfig(
                colors: [.hex("#00C2A8"), .hex("#1E5AFF"), .hex("#7A2BFF"), .hex("#10183A")],
                speed: 0.35, grain: 0.045, warp: 0.9, brightness: 1.0, style: .aurora, fps: 30)),
        GradientPreset(
            id: "sunset",
            name: "Sunset",
            config: GradientConfig(
                colors: [.hex("#FFB03A"), .hex("#FF5E62"), .hex("#A33A9E"), .hex("#2B1055")],
                speed: 0.4, grain: 0.05, warp: 1.0, brightness: 1.02, style: .aurora, fps: 30)),
        GradientPreset(
            id: "lagoon",
            name: "Lagoon",
            config: GradientConfig(
                colors: [.hex("#0FF0B3"), .hex("#0AA6D6"), .hex("#0B3B6F"), .hex("#06122A")],
                speed: 0.3, grain: 0.04, warp: 1.3, brightness: 0.98, style: .liquid, fps: 30)),
        GradientPreset(
            id: "ember",
            name: "Ember",
            config: GradientConfig(
                colors: [.hex("#FF2E00"), .hex("#FF8A00"), .hex("#3A0A00")],
                speed: 0.5, grain: 0.07, warp: 1.4, brightness: 1.0, style: .liquid, fps: 30)),
        GradientPreset(
            id: "mono-noir",
            name: "Noir",
            config: GradientConfig(
                colors: [.hex("#1A1A1F"), .hex("#3A3A45"), .hex("#0A0A0C")],
                speed: 0.2, grain: 0.09, warp: 0.7, brightness: 0.9, style: .aurora, fps: 24)),
        GradientPreset(
            id: "cotton",
            name: "Cotton",
            config: GradientConfig(
                colors: [.hex("#FFD3E0"), .hex("#C9E4FF"), .hex("#E4D3FF"), .hex("#FFF6E6")],
                speed: 0.28, grain: 0.03, warp: 0.85, brightness: 1.08, style: .aurora, fps: 30)),
        GradientPreset(
            id: "nebula",
            name: "Nebula",
            config: GradientConfig(
                colors: [.hex("#5B2A86"), .hex("#0E4D92"), .hex("#C2407E"), .hex("#05010F")],
                speed: 0.42, grain: 0.06, warp: 1.5, brightness: 1.0, style: .halo, fps: 30)),
    ]

    public static var `default`: GradientPreset { all[0] }

    public static func preset(id: String) -> GradientPreset? {
        all.first { $0.id == id }
    }
}
