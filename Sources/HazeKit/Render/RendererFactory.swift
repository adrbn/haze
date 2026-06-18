import Foundation

/// Builds the right `WallpaperRenderer` for a given `ContentItem`. Returns
/// `nil` if the backing file is missing or the item is malformed.
public enum RendererFactory {
    public static func makeRenderer(for item: ContentItem, fpsCap: Int = 0, muted: Bool = true) -> WallpaperRenderer? {
        switch item.type {
        case .video:
            guard let url = item.fileURL else { return nil }
            return VideoRenderer(url: url, scaling: item.settings.scaling, rate: item.settings.speed, muted: muted)
        case .animatedImage:
            guard let url = item.fileURL else { return nil }
            return AnimatedImageRenderer(url: url, scaling: item.settings.scaling)
        case .image:
            guard let url = item.fileURL else { return nil }
            return StaticImageRenderer(url: url, scaling: item.settings.scaling)
        case .gradient:
            guard let config = item.gradient else { return nil }
            return GradientRenderer(config: config, fpsCap: fpsCap)
        case .shaderGradient:
            guard let config = item.shaderGradient else { return nil }
            return ShaderGradientRenderer(config: config, fpsCap: fpsCap)
        }
    }
}
