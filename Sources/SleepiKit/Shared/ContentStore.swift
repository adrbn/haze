import Foundation

/// Filesystem layout shared between the app and the screensaver.
///
/// Both processes run as the user and are non-sandboxed, so a plain directory
/// under Application Support is reachable from either side — no App Group needed.
public enum ContentStore {
    public static let appName = "Sleepi"

    /// Test hook: when set, all paths resolve under this directory instead of
    /// Application Support. Production code never sets this.
    public static var overrideRootURL: URL?

    /// `~/Library/Application Support/Sleepi`
    public static var rootURL: URL {
        if let overrideRootURL { return overrideRootURL }
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    public static var mediaURL: URL { rootURL.appendingPathComponent("Media", isDirectory: true) }
    public static var thumbnailsURL: URL { rootURL.appendingPathComponent("Thumbnails", isDirectory: true) }
    public static var manifestURL: URL { rootURL.appendingPathComponent("library.json", isDirectory: false) }
    public static var settingsURL: URL { rootURL.appendingPathComponent("settings.json", isDirectory: false) }

    /// Creates the directory tree if needed. Returns `false` only on a real I/O error.
    @discardableResult
    public static func ensureDirectories() -> Bool {
        let fm = FileManager.default
        do {
            for dir in [rootURL, mediaURL, thumbnailsURL] {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return true
        } catch {
            Log.library.error("Failed to create content directories: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
