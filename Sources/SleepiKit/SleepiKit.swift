import Foundation

/// Public entry points shared by the app and the screensaver.
public enum SleepiKit {
    public static let version = "0.1.0"

    /// Resolve which item the screensaver should display, reading the shared
    /// settings + manifest. Falls back gracefully so the saver always has
    /// *something* to render.
    public static func screensaverItem() -> ContentItem {
        let settings = JSONStore.load(AppSettings.self, from: ContentStore.settingsURL) ?? .default
        let manifest = JSONStore.load(LibraryManifest.self, from: ContentStore.manifestURL) ?? LibraryManifest()

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

    public static func globalFPSCap() -> Int {
        (JSONStore.load(AppSettings.self, from: ContentStore.settingsURL) ?? .default).globalFPSCap
    }
}
