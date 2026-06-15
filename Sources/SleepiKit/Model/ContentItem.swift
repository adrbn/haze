import Foundation

/// Per-item playback preferences.
public struct ItemSettings: Codable, Hashable, Sendable {
    public var fps: Int          // preferred frame rate (0 = follow display)
    public var scaling: Scaling

    public init(fps: Int = 0, scaling: Scaling = .fill) {
        self.fps = fps
        self.scaling = scaling
    }
}

public enum Scaling: String, Codable, Sendable, CaseIterable {
    case fill     // aspect fill (cover), default
    case fit      // aspect fit (contain)
    case stretch  // distort to fill
    case center   // 1:1 centred

    public var displayName: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        case .stretch: return "Stretch"
        case .center: return "Center"
        }
    }
}

/// One library entry. File-backed items (video/animated/image) store a path
/// relative to the Media directory; gradients carry an inline `GradientConfig`.
public struct ContentItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var type: ContentType
    public var name: String
    public var author: String?
    public var tags: [String]
    public var relativePath: String?     // under ContentStore.mediaURL
    public var thumbnailPath: String?    // under ContentStore.thumbnailsURL
    public var gradient: GradientConfig?              // for .gradient items
    public var shaderGradient: ShaderGradientConfig?  // for .shaderGradient items
    public var settings: ItemSettings
    public var addedAt: Date

    public init(id: UUID = UUID(),
                type: ContentType,
                name: String,
                author: String? = nil,
                tags: [String] = [],
                relativePath: String? = nil,
                thumbnailPath: String? = nil,
                gradient: GradientConfig? = nil,
                shaderGradient: ShaderGradientConfig? = nil,
                settings: ItemSettings = ItemSettings(),
                addedAt: Date = Date()) {
        self.id = id
        self.type = type
        self.name = name
        self.author = author
        self.tags = tags
        self.relativePath = relativePath
        self.thumbnailPath = thumbnailPath
        self.gradient = gradient
        self.shaderGradient = shaderGradient
        self.settings = settings
        self.addedAt = addedAt
    }

    public var fileURL: URL? {
        relativePath.map { ContentStore.mediaURL.appendingPathComponent($0) }
    }

    public var thumbnailURL: URL? {
        thumbnailPath.map { ContentStore.thumbnailsURL.appendingPathComponent($0) }
    }

    /// A gradient item built from a config (no backing file).
    public static func gradient(_ config: GradientConfig, name: String, author: String? = nil) -> ContentItem {
        ContentItem(type: .gradient, name: name, author: author, gradient: config)
    }

    /// A shadergradient.co-style 3D gradient item (no backing file).
    public static func shaderGradient(_ config: ShaderGradientConfig, name: String, author: String? = nil) -> ContentItem {
        ContentItem(type: .shaderGradient, name: name, author: author, shaderGradient: config)
    }
}
