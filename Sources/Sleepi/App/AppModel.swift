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
    /// Live speed of the playing wallpaper (drives the sidebar slider).
    @Published var currentWallpaperSpeed: Double = 0.5

    private var speedSaveWork: DispatchWorkItem?

    private init() {
        settings = JSONStore.load(AppSettings.self, from: ContentStore.settingsURL) ?? .default
        library.seedDefaultsIfNeeded()
        seedShaderPresets()
        items = library.items
        settings.launchAtLogin = LaunchAtLogin.isEnabled
        syncCurrentSpeed()
    }

    /// Add bundled Fluid (3D) presets not yet in the library, tracking seeded IDs
    /// so new presets appear on update without duplicating or resurrecting deleted ones.
    private func seedShaderPresets() {
        var seeded = Set(settings.seededGradientPresetIDs)
        if seeded.isEmpty {
            let existing = Set(library.items.filter { $0.type == .shaderGradient }.map(\.name))
            for preset in ShaderGradientPresets.all where existing.contains(preset.name) {
                seeded.insert(preset.id)
            }
        }
        let toAdd = ShaderGradientPresets.all.filter { !seeded.contains($0.id) }
        for preset in toAdd {
            library.addShaderGradient(preset.config, name: preset.name)
            seeded.insert(preset.id)
        }
        settings.seededGradientPresetIDs = seeded.sorted()
        if !toAdd.isEmpty { persist() }
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
        syncCurrentSpeed()
        syncSystemWallpaper()
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
        currentWallpaperSpeed = speed(of: item)
        syncSystemWallpaper()
    }

    /// Generate the wallpaper poster. It's always shown behind the live Metal
    /// view (so Space swipes / Mission Control aren't black), and — when the user
    /// opts in — also set as the macOS desktop picture (for lock / login),
    /// capturing their original once so it can be restored.
    private func syncSystemWallpaper() {
        guard let item = currentWallpaper else { return }
        let setSystem = settings.matchSystemWallpaper
        if setSystem {
            let captured = SystemWallpaper.captureOriginal(settings)
            if captured.savedSystemWallpaperPath != settings.savedSystemWallpaperPath {
                settings = captured
                persist()
            }
        }
        SystemWallpaper.apply(for: item, setSystemPicture: setSystem) { [weak self] url in
            guard let self else { return }
            self.wallpaper.setFallbackImage(url)
            if setSystem { self.reassertWallpaperWindows() }
        }
    }

    /// macOS layers its desktop picture above our desktop-level windows when it
    /// changes, so re-raise ours immediately and again after it settles.
    private func reassertWallpaperWindows() {
        wallpaper.reassert()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.wallpaper.reassert()
        }
    }

    // MARK: Speed control (sidebar slider)

    var currentSupportsSpeed: Bool {
        switch currentWallpaper?.type {
        case .gradient, .shaderGradient, .video: return true
        default: return false
        }
    }

    var currentSpeedRange: ClosedRange<Double> {
        currentWallpaper?.type == .video ? 0.25...2.0 : 0.0...1.0
    }

    private func speed(of item: ContentItem?) -> Double {
        guard let item else { return 0.5 }
        if let g = item.gradient { return g.speed }
        if let sg = item.shaderGradient { return sg.speed }
        return item.settings.speed
    }

    func syncCurrentSpeed() { currentWallpaperSpeed = speed(of: currentWallpaper) }

    /// Live-set the playing wallpaper's speed: applies to the desktop immediately,
    /// keeps the manifest in memory while dragging, and saves once it settles.
    func setCurrentSpeed(_ value: Double) {
        currentWallpaperSpeed = value
        guard var item = currentWallpaper else { return }
        if item.gradient != nil { item.gradient?.speed = value }
        else if item.shaderGradient != nil { item.shaderGradient?.speed = value }
        else { item.settings.speed = value }

        wallpaper.liveUpdate(item: item)
        library.update(item, persist: false)

        speedSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.library.save()
            self.items = self.library.items
        }
        speedSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
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
            syncCurrentSpeed()
            syncSystemWallpaper()
        }
    }

    /// Rename an item without reapplying/restarting the wallpaper.
    func rename(_ item: ContentItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else { return }
        var updated = item
        updated.name = trimmed
        library.update(updated)
        refresh()
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
                syncSystemWallpaper()
            } else {
                wallpaper.clear()
            }
            syncCurrentSpeed()
        }
        if settings.screensaverItemID == item.id {
            settings.screensaverItemID = nil
        }
        persist()
    }

    func updateSettings(_ newSettings: AppSettings) {
        let launchChanged = newSettings.launchAtLogin != settings.launchAtLogin
        let soundChanged = newSettings.videoSoundEnabled != settings.videoSoundEnabled
        let matchChanged = newSettings.matchSystemWallpaper != settings.matchSystemWallpaper
        settings = newSettings
        wallpaper.updateSettings(newSettings)
        if launchChanged { LaunchAtLogin.setEnabled(newSettings.launchAtLogin) }
        if soundChanged, let current = currentWallpaper, current.type == .video {
            wallpaper.apply(item: current, settings: settings)   // rebuild video with new mute state
        }
        persist()
        if matchChanged {
            if newSettings.matchSystemWallpaper {
                syncSystemWallpaper()
            } else {
                SystemWallpaper.restore(savedPath: newSettings.savedSystemWallpaperPath) { [weak self] in
                    self?.reassertWallpaperWindows()
                }
            }
        }
    }

    // MARK: Favorites

    func isFavorite(_ item: ContentItem) -> Bool {
        settings.favoriteItemIDs.contains(item.id.uuidString)
    }

    func toggleFavorite(_ item: ContentItem) {
        let id = item.id.uuidString
        if let idx = settings.favoriteItemIDs.firstIndex(of: id) {
            settings.favoriteItemIDs.remove(at: idx)
        } else {
            settings.favoriteItemIDs.append(id)
        }
        persist()
    }

    /// Items in a category, optionally floating one (the currently-applied
    /// wallpaper/screensaver) to the front so it's always visible first.
    func items(in category: LibraryCategory, pinnedFirst pinnedID: UUID? = nil) -> [ContentItem] {
        let filtered = items.filter { category.matches($0, isFavorite: isFavorite($0)) }
        guard let pinnedID, let idx = filtered.firstIndex(where: { $0.id == pinnedID }) else {
            return filtered
        }
        var result = filtered
        result.insert(result.remove(at: idx), at: 0)
        return result
    }

    func persist() {
        JSONStore.save(settings, to: ContentStore.settingsURL)
    }
}
