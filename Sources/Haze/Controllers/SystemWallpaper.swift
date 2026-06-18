import AppKit
import AVFoundation
import HazeKit

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

    /// Generate a matching poster for `item` off the main thread. It's always handed
    /// back via `then` (shown *in-window* behind the live view, so Space swipes /
    /// Mission Control show a still gradient instead of black), and — when the user
    /// opts in — also set as the macOS desktop picture (so the Spaces switcher / lock
    /// / login, which draw the system picture, match the live wallpaper too).
    static func apply(for item: ContentItem,
                      setSystemPicture: Bool,
                      then: (@MainActor @Sendable (URL?) -> Void)? = nil) {
        Task.detached(priority: .utility) {
            let posterURL = makePoster(for: item)
            await MainActor.run {
                if setSystemPicture, let posterURL { setDesktopPicture(posterURL) }
                then?(posterURL)
            }
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
        // The supported call above can't override a Space whose desktop the user
        // set to a *colour* (or other non-image choice) in System Settings — that
        // Space, and the lock screen which mirrors it, keep the old background.
        // Heal those by rewriting the wallpaper store directly (off the main thread).
        DispatchQueue.global(qos: .utility).async { reconcileWallpaperStore(posterURL: url) }
    }

    // MARK: - Wallpaper store self-heal (macOS 26 Tahoe / Sonoma+)

    /// On Sonoma+ the wallpaper lives in `com.apple.wallpaper`'s per-Space
    /// `Index.plist`. `setDesktopImageURL` updates image Spaces but leaves a Space
    /// whose user explicitly chose a *colour/video* untouched (the lock screen,
    /// which has no entry of its own, then mirrors that stale choice). Rewrite any
    /// such non-image desktop to our poster — reusing the exact image entry that
    /// `setDesktopImageURL` just wrote as a template — then reload the agent. Only
    /// reloads when something actually changed, so normal switches don't flash.
    private static let imageProvider = "com.apple.wallpaper.choice.image"

    nonisolated private static func reconcileWallpaperStore(posterURL: URL) {
        let store = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let data = try? Data(contentsOf: store),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let template = findTemplateContent(root, posterURL: posterURL) else { return }

        var changed = false
        let healed = rewriteNonImageDesktops(root, template: template, changed: &changed)
        guard changed,
              let out = try? PropertyListSerialization.data(fromPropertyList: healed, format: .binary, options: 0)
        else { return }
        do {
            try out.write(to: store)
            reloadWallpaperAgent()
            Log.app.info("Healed non-image desktop Space(s) to match the wallpaper poster")
        } catch {
            Log.app.error("Failed to write wallpaper store: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The `Content` of the first image desktop whose configuration points at
    /// `posterURL` — i.e. the one `setDesktopImageURL` just created. Reused as the
    /// template so we match Apple's exact (binary-plist) format instead of building it.
    nonisolated private static func findTemplateContent(_ node: Any, posterURL: URL) -> [String: Any]? {
        if let dict = node as? [String: Any] {
            if let desktop = dict["Desktop"] as? [String: Any],
               let content = desktop["Content"] as? [String: Any],
               contentImageURL(content) == posterURL.standardizedFileURL {
                return content
            }
            for value in dict.values {
                if let found = findTemplateContent(value, posterURL: posterURL) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = findTemplateContent(value, posterURL: posterURL) { return found }
            }
        }
        return nil
    }

    /// Rebuild the tree, replacing every `Desktop` whose choice is *not* an image
    /// with `template`. Leaves image desktops (handled by `setDesktopImageURL`) and
    /// all `Idle`/screen-saver entries alone.
    nonisolated private static func rewriteNonImageDesktops(_ node: Any, template: [String: Any], changed: inout Bool) -> Any {
        if var dict = node as? [String: Any] {
            for (key, value) in dict {
                if key == "Desktop", var desktop = value as? [String: Any],
                   let content = desktop["Content"] as? [String: Any],
                   contentProvider(content) != imageProvider {
                    desktop["Content"] = template
                    dict[key] = desktop
                    changed = true
                } else {
                    dict[key] = rewriteNonImageDesktops(value, template: template, changed: &changed)
                }
            }
            return dict
        } else if let array = node as? [Any] {
            return array.map { rewriteNonImageDesktops($0, template: template, changed: &changed) }
        }
        return node
    }

    nonisolated private static func contentProvider(_ content: [String: Any]) -> String? {
        (content["Choices"] as? [Any])?.first.flatMap { ($0 as? [String: Any])?["Provider"] as? String }
    }

    /// Decode a desktop `Content`'s image configuration (a nested binary plist) to
    /// its file URL, if it is an image choice.
    nonisolated private static func contentImageURL(_ content: [String: Any]) -> URL? {
        guard contentProvider(content) == imageProvider,
              let choice = (content["Choices"] as? [Any])?.first as? [String: Any],
              let cfgData = choice["Configuration"] as? Data,
              let cfg = try? PropertyListSerialization.propertyList(from: cfgData, format: nil) as? [String: Any],
              let urlDict = cfg["url"] as? [String: Any],
              let relative = urlDict["relative"] as? String,
              let url = URL(string: relative) else { return nil }
        return url.standardizedFileURL
    }

    /// Reload only the wallpaper agent so it re-reads the store. We deliberately do
    /// NOT restart `cfprefsd` (the system-wide preferences daemon) — that flickers
    /// the whole UI. `WallpaperAgent` is wallpaper-specific and relaunches on demand;
    /// restarting just it re-reads `Index.plist` with only a brief wallpaper redraw.
    nonisolated private static func reloadWallpaperAgent() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["WallpaperAgent"]
        task.standardError = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // killall returns non-zero if the process isn't running — harmless.
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
