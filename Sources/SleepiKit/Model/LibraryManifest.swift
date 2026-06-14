import Foundation

/// On-disk catalogue of every imported / created item. Persisted as
/// `library.json` in the shared content directory.
public struct LibraryManifest: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var items: [ContentItem]

    public init(version: Int = LibraryManifest.currentVersion, items: [ContentItem] = []) {
        self.version = version
        self.items = items
    }
}
