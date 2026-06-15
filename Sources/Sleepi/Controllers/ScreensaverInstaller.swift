import AppKit
import SleepiKit

/// Installs the bundled `SleepiSaver.saver` into `~/Library/Screen Savers` and
/// deep-links to the screensaver section of System Settings (macOS owns the
/// idle timer, so activation timing is configured there).
enum ScreensaverInstaller {
    static var bundledSaverURL: URL? {
        Bundle.main.url(forResource: "SleepiSaver", withExtension: "saver")
    }

    static var installURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Screen Savers/SleepiSaver.saver", isDirectory: true)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installURL.path)
    }

    @discardableResult
    static func install() -> Bool {
        guard let source = bundledSaverURL else {
            Log.app.error("Bundled SleepiSaver.saver not found in app bundle")
            return false
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: installURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: installURL.path) {
                try fm.removeItem(at: installURL)
            }
            try fm.copyItem(at: source, to: installURL)
            Log.app.info("Installed screensaver to \(installURL.path, privacy: .public)")
            return true
        } catch {
            Log.app.error("Screensaver install failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func openSystemSettings() {
        // The Screen Saver pane moved around across macOS releases. On macOS 26
        // (Tahoe) it no longer exists as a standalone pane — its controls live
        // inside the "Wallpaper" pane (reached via its "Screen Saver…" button) —
        // so deep-linking `ScreenSaver-Settings` lands on General instead.
        // `NSWorkspace.open` returns true even for an unresolved pane, so we
        // can't rely on the return value to fall through; branch on the OS.
        let candidates: [String]
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 {
            candidates = [
                "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension",
                "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension",
            ]
        } else {
            candidates = [
                "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension",
                "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension",
            ]
        }
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}
