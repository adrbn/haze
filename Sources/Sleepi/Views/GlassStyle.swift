import SwiftUI
import AppKit
import SleepiKit

/// Sidebar destinations.
enum AppTab: String, CaseIterable, Identifiable {
    case wallpapers, gradients, screensaver, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .wallpapers: return "Wallpapers"
        case .gradients: return "Gradients"
        case .screensaver: return "Screensaver"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .wallpapers: return "photo.on.rectangle.angled"
        case .gradients: return "circle.hexagongrid.fill"
        case .screensaver: return "moon.zzz.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

extension View {
    /// Liquid Glass on macOS 26, `.ultraThinMaterial` glass fallback on 15.
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    /// A soft rounded card used throughout the library grids.
    func glassCard(cornerRadius: CGFloat = 18, selected: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    selected ? Color.accentColor : Color.white.opacity(0.10),
                    lineWidth: selected ? 3 : 1)
            )
            .shadow(color: .black.opacity(selected ? 0.35 : 0.18),
                    radius: selected ? 16 : 8, y: 6)
    }
}

extension RGBAColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        self.init(r: Double(ns.redComponent),
                  g: Double(ns.greenComponent),
                  b: Double(ns.blueComponent),
                  a: Double(ns.alphaComponent))
    }
}

/// Cheap static representation of a 2D gradient (used for grid thumbnails).
struct GradientSwatch: View {
    let config: GradientConfig
    var body: some View {
        LinearGradient(
            colors: config.colors.map(\.swiftUIColor),
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }
}

/// Cheap static representation of a 3D ShaderGradient (3-stop, rolled to match).
struct ShaderGradientSwatch: View {
    let config: ShaderGradientConfig
    var body: some View {
        LinearGradient(
            colors: config.colors.map(\.swiftUIColor),
            startPoint: .top,
            endPoint: .bottom)
        .rotationEffect(.degrees(config.rotationZ))
        .scaleEffect(2.0)   // cover corners after the roll
    }
}
