import AppKit
import AVFoundation
import SleepiKit

/// Sets the macOS desktop picture to a static "poster" of the chosen wallpaper,
/// so Mission Control, the lock screen, and login — which all render from the
/// *system* desktop picture, not third-party desktop-level windows — show
/// something consistent with the live wallpaper instead of the user's old
/// background. The original is captured once so it can be restored.
enum SystemWallpaper {
    /// Capture the user's current desktop picture once (before we overwrite it),
    /// returning a new settings value with `savedSystemWallpaperPath` filled in.
    static func captureOriginal(_ settings: AppSettings) -> AppSettings {
        guard settings.savedSystemWallpaperPath == nil else { return settings }
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              !url.path.contains("/Posters/") else { return settings }
        var updated = settings
        updated.savedSystemWallpaperPath = url.path
        Log.app.info("Captured original desktop picture: \(url.path, privacy: .public)")
        return updated
    }

    /// Generate a poster for `item` and set it as the desktop picture on every
    /// screen. Heavy work (frame extraction / drawing) runs off the main thread.
    static func apply(for item: ContentItem) {
        Task.detached(priority: .utility) {
            guard let posterURL = makePoster(for: item) else { return }
            await MainActor.run { setDesktopPicture(posterURL) }
        }
    }

    /// Restore the captured original desktop picture, if any.
    @MainActor
    static func restore(savedPath: String?) {
        guard let savedPath, FileManager.default.fileExists(atPath: savedPath) else { return }
        setDesktopPicture(URL(fileURLWithPath: savedPath))
    }

    // MARK: - Setting the picture

    @MainActor
    private static func setDesktopPicture(_ url: URL) {
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true,
        ]
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
            } catch {
                Log.app.error("Failed to set desktop picture: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Poster generation

    /// Returns a file URL suitable as a desktop picture. File-backed items point
    /// straight at their media (or a video poster frame); gradients render a
    /// matching still from their colours.
    private static func makePoster(for item: ContentItem) -> URL? {
        switch item.type {
        case .image, .animatedImage:
            return item.fileURL                       // a still / first GIF frame is fine
        case .video:
            return videoPoster(for: item)
        case .gradient:
            return gradientPoster(id: item.id, colors: item.gradient?.colors ?? [])
        case .shaderGradient:
            return gradientPoster(id: item.id, colors: item.shaderGradient?.colors ?? [])
        }
    }

    private static func videoPoster(for item: ContentItem) -> URL? {
        guard let fileURL = item.fileURL else { return nil }
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.2, preferredTimescale: 600)
        guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return writeImage(NSBitmapImageRep(cgImage: cg), id: item.id, signature: item.relativePath ?? "")
    }

    private static func gradientPoster(id: UUID, colors: [RGBAColor]) -> URL? {
        let nsColors = posterColors(colors)
        let size = posterSize()
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        // Bitmap-backed context — safe to draw off the main thread (unlike NSImage.lockFocus).
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let rect = NSRect(origin: .zero, size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        NSGradient(colors: nsColors)?.draw(in: rect, angle: -45)   // diagonal sweep, like the swatches
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let signature = colors.map { "\($0.r),\($0.g),\($0.b)" }.joined(separator: "|")
        return writeImage(rep, id: id, signature: signature)
    }

    /// At least two opaque colours for `NSGradient`.
    private static func posterColors(_ colors: [RGBAColor]) -> [NSColor] {
        let mapped = colors.prefix(6).map {
            NSColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: 1)
        }
        switch mapped.count {
        case 0: return [.black, NSColor(white: 0.1, alpha: 1)]
        case 1: return [mapped[0], mapped[0]]
        default: return mapped
        }
    }

    /// Poster resolution, capped so smooth gradients don't balloon to tens of MB.
    private static func posterSize() -> NSSize {
        let maxLongSide: CGFloat = 2560
        guard let screen = NSScreen.main else { return NSSize(width: maxLongSide, height: 1600) }
        let frame = screen.frame
        let longSide = max(frame.width, frame.height)
        let scale = min(maxLongSide / longSide, 2)
        return NSSize(width: frame.width * scale, height: frame.height * scale)
    }

    /// Write a JPEG under Posters/, keyed by item id + a content signature so the
    /// filename changes when the content does (forcing macOS to refresh). Old
    /// posters for the same id are removed.
    private static func writeImage(_ rep: NSBitmapImageRep, id: UUID, signature: String) -> URL? {
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return nil }
        let fm = FileManager.default
        let dir = ContentStore.postersURL
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let prefix = id.uuidString
        if let stale = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in stale where url.lastPathComponent.hasPrefix(prefix) { try? fm.removeItem(at: url) }
        }
        let url = dir.appendingPathComponent("\(prefix)-\(stableHash(signature)).jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Log.app.error("Failed to write poster: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Deterministic djb2 hash (String.hashValue is randomised per run).
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 5381
        for byte in string.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return String(hash, radix: 36)
    }
}
