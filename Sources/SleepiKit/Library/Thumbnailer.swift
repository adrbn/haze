import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Generates and writes small PNG thumbnails for imported media.
public enum Thumbnailer {
    public static let maxPixelSize = 640

    public static func generate(for url: URL, type: ContentType) -> CGImage? {
        switch type {
        case .video: return videoThumbnail(url)
        case .image, .animatedImage: return imageThumbnail(url)
        case .gradient: return nil
        }
    }

    static func videoThumbnail(_ url: URL) -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        return try? generator.copyCGImage(at: time, actualTime: nil)
    }

    static func imageThumbnail(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    @discardableResult
    public static func write(_ image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}
