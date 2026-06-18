import Foundation

/// Public entry points shared by the app and the screensaver.
public enum HazeKit {
    public static let version = "0.1.0"

    /// The content + FPS cap the screensaver should use, read from the shared
    /// settings + manifest in a single pass. Falls back gracefully so the saver
    /// always has *something* to render.
    public static func screensaverContent() -> (item: ContentItem, fpsCap: Int) {
        let settings = JSONStore.load(AppSettings.self, from: ContentStore.settingsURL) ?? .default
        let manifest = JSONStore.load(LibraryManifest.self, from: ContentStore.manifestURL) ?? LibraryManifest()
        return (resolve(settings: settings, manifest: manifest), settings.globalFPSCap)
    }

    /// Resolve preferred screensaver → wallpaper → first gradient → default preset.
    static func resolve(settings: AppSettings, manifest: LibraryManifest) -> ContentItem {
        if let id = settings.screensaverItemID,
           let item = manifest.items.first(where: { $0.id == id }) {
            return item
        }
        if let id = settings.wallpaperItemID,
           let item = manifest.items.first(where: { $0.id == id }) {
            return item
        }
        if let gradient = manifest.items.first(where: { $0.type == .gradient }) {
            return gradient
        }
        return GradientPresets.default.makeItem()
    }
}
