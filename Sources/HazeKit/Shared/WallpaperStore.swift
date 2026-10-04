import Foundation

/// Pure surgery on macOS's wallpaper store (`com.apple.wallpaper`'s `Index.plist`).
/// Reading and writing the file, and reloading the agent afterwards, is the
/// caller's job — everything here is a value transform, so it can be tested.
///
/// The store keeps **one desktop picture per Space**, and `setDesktopImageURL`
/// only ever writes the Space that is active at the time. A user with many Spaces
/// therefore ends up with most of them still pointing at whichever poster was
/// current the last time that Space happened to be frontmost. That matters
/// because macOS derives the menu bar's light/dark treatment — and the pale
/// legibility backdrop it draws across the top of the screen — from the *current
/// Space's* desktop picture, not from the live wallpaper window. A Space left on
/// a bright old poster gets a pale band over a dark wallpaper, until the user
/// re-picks the preset while standing on that particular Space.
public enum WallpaperStore {
    public static let imageProvider = "com.apple.wallpaper.choice.image"

    public static var indexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    public enum HealOutcome {
        /// Nothing in the store points at the new poster yet. `setDesktopImageURL`
        /// is an async hop into WallpaperAgent, so there is no entry to copy
        /// Apple's exact (nested binary plist) format from — try again shortly.
        case notReady
        /// Every desktop we own already shows the new poster: no write, no agent
        /// reload, no wallpaper flash.
        case upToDate
        case healed(root: Any, desktops: Int)
    }

    /// Point every desktop Haze owns at `posterURL`, reusing the entry
    /// `setDesktopImageURL` just wrote as the template so the format matches
    /// Apple's byte for byte.
    public static func heal(_ root: Any, posterURL: URL, posterDirectory: URL) -> HealOutcome {
        guard let template = templateContent(root, posterURL: posterURL) else { return .notReady }
        var healed = 0
        let rewritten = rewriteDesktops(root, template: template, posterURL: posterURL,
                                        posterDirectory: posterDirectory, healed: &healed)
        return healed == 0 ? .upToDate : .healed(root: rewritten, desktops: healed)
    }

    // MARK: Predicate

    /// Whether this desktop is one for Haze to take over:
    ///
    /// * a **non-image** choice (a colour, or a dynamic/video wallpaper) —
    ///   `setDesktopImageURL` cannot reach those at all; or
    /// * an image choice still pointing at one of **our own older posters** — the
    ///   common case, left behind on every Space the user wasn't looking at when
    ///   they picked a new wallpaper.
    ///
    /// Anything else is a picture the user chose, and is never touched.
    static func needsRewrite(_ content: [String: Any], posterURL: URL, posterDirectory: URL) -> Bool {
        guard provider(content) == imageProvider else { return true }
        guard let url = imageURL(content), url != posterURL.standardizedFileURL else { return false }
        return isPoster(url, in: posterDirectory)
    }

    /// A file sitting directly in our posters folder. Deliberately an exact parent
    /// match rather than a path prefix, so an unrelated file in a lookalike
    /// subfolder is never mistaken for ours.
    static func isPoster(_ url: URL, in directory: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path
    }

    // MARK: Tree walking

    /// Rebuild the tree, replacing the `Content` of every desktop that needs it.
    /// `Idle` (screen saver) entries live alongside desktops and are left alone.
    private static func rewriteDesktops(_ node: Any, template: [String: Any], posterURL: URL,
                                        posterDirectory: URL, healed: inout Int) -> Any {
        if var dict = node as? [String: Any] {
            for (key, value) in dict {
                if key == "Desktop", var desktop = value as? [String: Any],
                   let content = desktop["Content"] as? [String: Any],
                   needsRewrite(content, posterURL: posterURL, posterDirectory: posterDirectory) {
                    desktop["Content"] = template
                    dict[key] = desktop
                    healed += 1
                } else {
                    dict[key] = rewriteDesktops(value, template: template, posterURL: posterURL,
                                                posterDirectory: posterDirectory, healed: &healed)
                }
            }
            return dict
        } else if let array = node as? [Any] {
            return array.map {
                rewriteDesktops($0, template: template, posterURL: posterURL,
                                posterDirectory: posterDirectory, healed: &healed)
            }
        }
        return node
    }

    /// The `Content` of the first desktop already pointing at `posterURL` — i.e.
    /// the one `setDesktopImageURL` just created. Reused verbatim as the template
    /// so we never have to construct Apple's format ourselves.
    private static func templateContent(_ node: Any, posterURL: URL) -> [String: Any]? {
        if let dict = node as? [String: Any] {
            if let desktop = dict["Desktop"] as? [String: Any],
               let content = desktop["Content"] as? [String: Any],
               imageURL(content) == posterURL.standardizedFileURL {
                return content
            }
            for value in dict.values {
                if let found = templateContent(value, posterURL: posterURL) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = templateContent(value, posterURL: posterURL) { return found }
            }
        }
        return nil
    }

    // MARK: Reading a Content

    static func provider(_ content: [String: Any]) -> String? {
        (content["Choices"] as? [Any])?.first.flatMap { ($0 as? [String: Any])?["Provider"] as? String }
    }

    /// Decode a desktop `Content`'s image configuration (itself a nested binary
    /// plist) to its file URL, if it is an image choice at all.
    static func imageURL(_ content: [String: Any]) -> URL? {
        guard provider(content) == imageProvider,
              let choice = (content["Choices"] as? [Any])?.first as? [String: Any],
              let data = choice["Configuration"] as? Data,
              let configuration = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let urlDict = configuration["url"] as? [String: Any],
              let relative = urlDict["relative"] as? String,
              let url = URL(string: relative) else { return nil }
        return url.standardizedFileURL
    }
}
