import AppKit
import SwiftUI
import SleepiKit

/// Central observable state for the UI. Owns the library + wallpaper controller
/// and persists settings on every change.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let library = LibraryManager()
    private let wallpaper = WallpaperController()

    @Published var settings: AppSettings
    @Published private(set) var items: [ContentItem] = []
    @Published var isPaused = false

    private init() {
        settings = JSONStore.load(AppSettings.self, from: ContentStore.settingsURL) ?? .default
        library.seedDefaultsIfNeeded()
        library.seedShaderGradientsIfNeeded()
        items = library.items
        settings.launchAtLogin = LaunchAtLogin.isEnabled
    }

    /// Called once from the app delegate after launch.
    func bootstrap() {
        wallpaper.configure(settings: settings)
        if let current = currentWallpaper {
            wallpaper.apply(item: current, settings: settings)
        } else if let first = items.first {
            settings.wallpaperItemID = first.id
            wallpaper.apply(item: first, settings: settings)
            persist()
        }
    }

    // MARK: Derived

    var currentWallpaper: ContentItem? {
        settings.wallpaperItemID.flatMap { id in items.first { $0.id == id } }
    }

    var currentScreensaver: ContentItem? {
        settings.screensaverItemID.flatMap { id in items.first { $0.id == id } }
    }

    func items(ofType type: ContentType) -> [ContentItem] {
        items.filter { $0.type == type }
    }

    // MARK: Mutations

    func refresh() { items = library.items }

    func setWallpaper(_ item: ContentItem) {
        settings.wallpaperItemID = item.id
        wallpaper.apply(item: item, settings: settings)
        persist()
    }

    func setScreensaver(_ item: ContentItem) {
        settings.screensaverItemID = item.id
        persist()
    }

    func togglePause() {
        isPaused.toggle()
        wallpaper.setUserPaused(isPaused)
    }

    func importFiles(_ urls: [URL]) {
        // Heavy work (copy + thumbnail decode) runs off the main thread; the
        // manifest mutation is committed back on the main actor.
        Task.detached(priority: .userInitiated) {
            var prepared: [ContentItem] = []
            var failures: [String] = []
            for url in urls {
                do { prepared.append(try LibraryManager.prepareImport(from: url)) }
                catch { failures.append(url.lastPathComponent) }
            }
            await MainActor.run {
                for item in prepared { self.library.add(item) }
                self.refresh()
                if !failures.isEmpty {
                    Log.app.error("Failed to import: \(failures.joined(separator: ", "), privacy: .public)")
                }
            }
        }
    }

    @discardableResult
    func addGradient(_ config: GradientConfig, name: String) -> ContentItem {
        let item = library.addGradient(config, name: name)
        refresh()
        return item
    }

    @discardableResult
    func addShaderGradient(_ config: ShaderGradientConfig, name: String) -> ContentItem {
        let item = library.addShaderGradient(config, name: name)
        refresh()
        return item
    }

    func updateItem(_ item: ContentItem) {
        library.update(item)
        refresh()
        if settings.wallpaperItemID == item.id {
            wallpaper.apply(item: item, settings: settings)
        }
    }

    /// Live-tweak the currently-playing wallpaper (e.g. speed) without a rebuild
    /// and without persisting on every slider tick.
    func liveUpdateCurrent(_ item: ContentItem) {
        guard settings.wallpaperItemID == item.id else { return }
        wallpaper.liveUpdate(item: item)
    }

    func deleteItem(_ item: ContentItem) {
        let wasWallpaper = settings.wallpaperItemID == item.id
        library.remove(id: item.id)
        refresh()
        if wasWallpaper {
            settings.wallpaperItemID = items.first?.id
            if let next = currentWallpaper {
                wallpaper.apply(item: next, settings: settings)
            } else {
                wallpaper.clear()
            }
        }
        if settings.screensaverItemID == item.id {
            settings.screensaverItemID = nil
        }
        persist()
    }

    func updateSettings(_ newSettings: AppSettings) {
        let launchChanged = newSettings.launchAtLogin != settings.launchAtLogin
        settings = newSettings
        wallpaper.updateSettings(newSettings)
        if launchChanged { LaunchAtLogin.setEnabled(newSettings.launchAtLogin) }
        persist()
    }

    func persist() {
        JSONStore.save(settings, to: ContentStore.settingsURL)
    }
}
