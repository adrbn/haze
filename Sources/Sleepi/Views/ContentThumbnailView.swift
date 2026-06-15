import SwiftUI
import AppKit
import SleepiKit

/// Small in-memory cache so grid scrolling doesn't re-decode thumbnails. Only
/// memory lookups happen synchronously; disk reads are done off the main thread
/// by the view.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func cached(_ url: URL) -> NSImage? {
        cache.object(forKey: url.path as NSString)
    }

    func store(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url.path as NSString)
    }

    func invalidate(_ url: URL) {
        cache.removeObject(forKey: url.path as NSString)
    }
}

extension ContentType {
    var symbol: String {
        switch self {
        case .video: return "film.fill"
        case .animatedImage: return "square.stack.3d.forward.dottedline.fill"
        case .gradient: return "circle.hexagongrid.fill"
        case .shaderGradient: return "cube.fill"
        case .image: return "photo.fill"
        }
    }

    var displayName: String {
        switch self {
        case .video: return "Video"
        case .animatedImage: return "Animated"
        case .gradient: return "Gradient"
        case .shaderGradient: return "Fluid"
        case .image: return "Image"
        }
    }
}

struct ContentThumbnailView: View {
    let item: ContentItem
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.black
            content
        }
        .task(id: item.id) { await loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if item.type == .gradient, let gradient = item.gradient {
            GradientSwatch(config: gradient)
        } else if item.type == .shaderGradient, let sg = item.shaderGradient {
            ShaderGradientSwatch(config: sg)
        } else if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: item.type.symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func loadIfNeeded() async {
        guard item.type != .gradient, let url = item.thumbnailURL else { return }
        if let cached = ThumbnailCache.shared.cached(url) {
            image = cached
            return
        }
        image = nil
        let loaded = await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
        guard let loaded else { return }
        ThumbnailCache.shared.store(loaded, for: url)
        image = loaded
    }
}
