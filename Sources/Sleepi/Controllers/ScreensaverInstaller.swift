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
        if let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings") {
            NSWorkspace.shared.open(url)
        }
    }
}
