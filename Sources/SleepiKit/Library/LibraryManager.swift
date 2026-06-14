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

    public func update(_ item: ContentItem) {
        guard let idx = manifest.items.firstIndex(where: { $0.id == item.id }) else { return }
        manifest.items[idx] = item
        save()
    }

    public func remove(id: UUID) {
        if let item = item(id: id) { deleteFiles(for: item) }
        manifest.items.removeAll { $0.id == id }
        save()
    }

    /// Import a media file: copy it into the Media directory, build a thumbnail,
    /// and append a `ContentItem`. The original is left untouched.
    @discardableResult
    public func importMedia(from sourceURL: URL, name: String? = nil) throws -> ContentItem {
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

        let item = ContentItem(
            id: id,
            type: type,
            name: name ?? sourceURL.deletingPathExtension().lastPathComponent,
            relativePath: relPath,
            thumbnailPath: thumbnailPath)
        return add(item)
    }

    @discardableResult
    public func addGradient(_ config: GradientConfig, name: String) -> ContentItem {
        add(ContentItem.gradient(config, name: name))
    }

    /// Populate the library with the bundled gradient presets if it's empty.
    public func seedDefaultsIfNeeded() {
        guard manifest.items.isEmpty else { return }
        for preset in GradientPresets.all {
            manifest.items.append(preset.makeItem())
        }
        save()
        Log.library.info("Seeded \(self.manifest.items.count, privacy: .public) default gradients")
    }

    private func deleteFiles(for item: ContentItem) {
        let fm = FileManager.default
        if let url = item.fileURL { try? fm.removeItem(at: url) }
        if let url = item.thumbnailURL { try? fm.removeItem(at: url) }
    }
}
