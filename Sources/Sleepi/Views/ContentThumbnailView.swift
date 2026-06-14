import SwiftUI
import AppKit
import SleepiKit

/// Small in-memory cache so grid scrolling doesn't re-decode thumbnails.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    func invalidate(_ url: URL) { cache.removeObject(forKey: url.path as NSString) }
}

extension ContentType {
    var symbol: String {
        switch self {
        case .video: return "film.fill"
        case .animatedImage: return "square.stack.3d.forward.dottedline.fill"
        case .gradient: return "circle.hexagongrid.fill"
        case .image: return "photo.fill"
        }
    }

    var displayName: String {
        switch self {
        case .video: return "Video"
        case .animatedImage: return "Animated"
        case .gradient: return "Gradient"
        case .image: return "Image"
        }
    }
}

struct ContentThumbnailView: View {
    let item: ContentItem

    var body: some View {
        ZStack {
            Color.black
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if item.type == .gradient, let gradient = item.gradient {
            GradientSwatch(config: gradient)
        } else if let url = item.thumbnailURL, let image = ThumbnailCache.shared.image(for: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: item.type.symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
