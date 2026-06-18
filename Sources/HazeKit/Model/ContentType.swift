import Foundation

/// The kind of content a `ContentItem` represents. Drives renderer selection.
public enum ContentType: String, Codable, Sendable, CaseIterable {
    case video
    case animatedImage   // GIF / APNG
    case gradient        // 2D Metal field, no backing file
    case shaderGradient  // 3D shadergradient.co-style surface, no backing file
    case image           // still

    /// True for both gradient kinds (neither is file-backed).
    public var isGradient: Bool { self == .gradient || self == .shaderGradient }

    public static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "hevc"]
    public static let animatedExtensions: Set<String> = ["gif", "apng"]
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "bmp", "webp"]

    /// Best-effort type inference from a file extension. Unknown → `.video`
    /// (the most common imported asset), so the importer can still validate it.
    public static func infer(from url: URL) -> ContentType {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) { return .video }
        if animatedExtensions.contains(ext) { return .animatedImage }
        if imageExtensions.contains(ext) { return .image }
        return .video
    }

    /// All file extensions accepted by the importer (gradients are not file-backed).
    public static var importableExtensions: [String] {
        Array(videoExtensions) + Array(animatedExtensions) + Array(imageExtensions)
    }
}
