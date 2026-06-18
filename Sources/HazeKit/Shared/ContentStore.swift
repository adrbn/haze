import Foundation
import Darwin

/// Filesystem layout shared between the app and the screensaver.
///
/// The app is non-sandboxed and writes here. The screensaver host
/// (`legacyScreenSaver`) IS sandboxed but has read-only access to the whole
/// disk — however, inside the sandbox `FileManager`'s `.applicationSupportDirectory`
/// redirects to the (empty) sandbox container. So we resolve the *real* home via
/// `getpwuid`, which both processes agree on, and the saver reads from it.
public enum ContentStore {
    public static let appName = "Haze"

    /// Test hook: when set, all paths resolve under this directory instead of
    /// Application Support. Production code never sets this.
    public static var overrideRootURL: URL?

    /// Real home directory, bypassing sandbox-container redirection.
    static var realHome: URL {
        // getpwuid reads the real passwd entry (not redirected by the sandbox).
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            let path = String(cString: dir)
            if !path.isEmpty, !path.contains("/Containers/") {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        // Fallback if getpwuid is restricted: reconstruct from the user name.
        let user = NSUserName()
        if !user.isEmpty {
            return URL(fileURLWithPath: "/Users/\(user)", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// `~/Library/Application Support/Haze` (real path, sandbox-proof)
    public static var rootURL: URL {
        if let overrideRootURL { return overrideRootURL }
        return realHome
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
    }

    public static var mediaURL: URL { rootURL.appendingPathComponent("Media", isDirectory: true) }
    public static var thumbnailsURL: URL { rootURL.appendingPathComponent("Thumbnails", isDirectory: true) }
    /// Static "poster" stills written here and set as the macOS desktop picture,
    /// so Mission Control / lock / login match the live wallpaper.
    public static var postersURL: URL { rootURL.appendingPathComponent("Posters", isDirectory: true) }
    public static var manifestURL: URL { rootURL.appendingPathComponent("library.json", isDirectory: false) }
    public static var settingsURL: URL { rootURL.appendingPathComponent("settings.json", isDirectory: false) }

    /// One-time rename migration: the app was previously called "Sleepi". If the
    /// user's data still lives in the old support folder and the new one doesn't
    /// exist yet, move it so their library and settings carry across the rename.
    private static func migrateLegacyDirectoryIfNeeded() {
        guard overrideRootURL == nil else { return }
        let fm = FileManager.default
        let legacy = realHome
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("Sleepi", isDirectory: true)
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: rootURL.path) else { return }
        do {
            try fm.moveItem(at: legacy, to: rootURL)
            Log.library.info("Migrated legacy 'Sleepi' data to 'Haze'")
        } catch {
            Log.library.error("Legacy data migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Creates the directory tree if needed. Returns `false` only on a real I/O error.
    @discardableResult
    public static func ensureDirectories() -> Bool {
        migrateLegacyDirectoryIfNeeded()
        let fm = FileManager.default
        do {
            for dir in [rootURL, mediaURL, thumbnailsURL, postersURL] {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return true
        } catch {
            Log.library.error("Failed to create content directories: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
