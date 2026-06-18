import Foundation

public enum LibraryError: LocalizedError {
    case unsupportedType(String)
    case copyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedType(let ext): return "Unsupported file type: .\(ext)"
        case .copyFailed(let reason): return "Could not import file: \(reason)"
        }
    }
}

/// Owns the on-disk library: imports media, generates thumbnails, persists the
/// JSON manifest, and seeds the bundled gradient presets on first run.
public final class LibraryManager {
    public private(set) var manifest: LibraryManifest

    public init() {
        ContentStore.ensureDirectories()
        manifest = JSONStore.load(LibraryManifest.self, from: ContentStore.manifestURL) ?? LibraryManifest()
        migrateSpeeds()
    }

    /// Gradient speed is now capped at 1.0 (2.0 looked too fast). Clamp any
    /// previously-saved gradients so they don't keep animating too fast.
    private func migrateSpeeds() {
        var changed = false
        for idx in manifest.items.indices {
            if let g = manifest.items[idx].gradient, g.speed > 1.0 {
                manifest.items[idx].gradient?.speed = 1.0
                changed = true
            }
            if let sg = manifest.items[idx].shaderGradient, sg.speed > 1.0 {
                manifest.items[idx].shaderGradient?.speed = 1.0
                changed = true
            }
        }
        if changed { save() }
    }

    public var items: [ContentItem] { manifest.items }

    public func items(ofType type: ContentType) -> [ContentItem] {
        manifest.items.filter { $0.type == type }
    }

    public func item(id: UUID) -> ContentItem? {
        manifest.items.first { $0.id == id }
    }

    @discardableResult
    public func save() -> Bool {
        JSONStore.save(manifest, to: ContentStore.manifestURL)
    }

    @discardableResult
    public func add(_ item: ContentItem) -> ContentItem {
        manifest.items.append(item)
        save()
        return item
    }

    public func update(_ item: ContentItem, persist: Bool = true) {
        guard let idx = manifest.items.firstIndex(where: { $0.id == item.id }) else { return }
        manifest.items[idx] = item
        if persist { save() }
    }

    public func remove(id: UUID) {
        if let item = item(id: id) { deleteFiles(for: item) }
        manifest.items.removeAll { $0.id == id }
        save()
    }

    /// Filesystem-only import work: copy the file into the Media directory and
    /// build a thumbnail, returning a ready `ContentItem`. Performs **no**
    /// manifest mutation, so it is safe to call off the main thread; commit the
    /// result with `add(_:)` on the owning thread.
    public static func prepareImport(from sourceURL: URL, name: String? = nil) throws -> ContentItem {
        let ext = sourceURL.pathExtension.lowercased()
        guard ContentType.importableExtensions.contains(ext) else {
            throw LibraryError.unsupportedType(ext.isEmpty ? "(none)" : ext)
        }
        let type = ContentType.infer(from: sourceURL)
        let id = UUID()
        let relPath = "\(id.uuidString).\(ext)"
        let destURL = ContentStore.mediaURL.appendingPathComponent(relPath)

        ContentStore.ensureDirectories()
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            throw LibraryError.copyFailed(error.localizedDescription)
        }

        var thumbnailPath: String?
        if let thumb = Thumbnailer.generate(for: destURL, type: type) {
            let thumbRel = "\(id.uuidString).png"
            if Thumbnailer.write(thumb, to: ContentStore.thumbnailsURL.appendingPathComponent(thumbRel)) {
                thumbnailPath = thumbRel
            }
        }

        return ContentItem(
            id: id,
            type: type,
            name: name ?? sourceURL.deletingPathExtension().lastPathComponent,
            relativePath: relPath,
            thumbnailPath: thumbnailPath)
    }

    /// Convenience: prepare + commit in one call (used by tests and synchronous
    /// callers). The original file is left untouched.
    @discardableResult
    public func importMedia(from sourceURL: URL, name: String? = nil) throws -> ContentItem {
        add(try Self.prepareImport(from: sourceURL, name: name))
    }

    @discardableResult
    public func addGradient(_ config: GradientConfig, name: String) -> ContentItem {
        add(ContentItem.gradient(config, name: name))
    }

    @discardableResult
    public func addShaderGradient(_ config: ShaderGradientConfig, name: String) -> ContentItem {
        add(ContentItem.shaderGradient(config, name: name))
    }

    /// Populate the library with the bundled 2D gradient presets if it's empty.
    public func seedDefaultsIfNeeded() {
        guard manifest.items.isEmpty else { return }
        for preset in GradientPresets.all {
            manifest.items.append(preset.makeItem())
        }
        save()
        Log.library.info("Seeded \(self.manifest.items.count, privacy: .public) default gradients")
    }

    /// Add the bundled 3D ShaderGradient presets if none are present yet
    /// (also migrates libraries created before 3D gradients existed).
    public func seedShaderGradientsIfNeeded() {
        guard !manifest.items.contains(where: { $0.type == .shaderGradient }) else { return }
        for preset in ShaderGradientPresets.all {
            manifest.items.append(preset.makeItem())
        }
        save()
        Log.library.info("Seeded \(ShaderGradientPresets.all.count, privacy: .public) ShaderGradient presets")
    }

    private func deleteFiles(for item: ContentItem) {
        let fm = FileManager.default
        if let url = item.fileURL { try? fm.removeItem(at: url) }
        if let url = item.thumbnailURL { try? fm.removeItem(at: url) }
    }
}
