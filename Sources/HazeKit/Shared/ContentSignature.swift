import Foundation

/// Stable signatures used to key cached artefacts — poster filenames — by the
/// content that produced them.
public enum ContentSignature {
    /// Deterministic djb2 hash, base 36. `String.hashValue` is randomised per
    /// process, so it cannot name a file that has to survive a relaunch.
    public static func hash(_ string: String) -> String {
        var hash: UInt64 = 5381
        for byte in string.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return String(hash, radix: 36)
    }

    /// A signature covering *every* field of a config.
    ///
    /// Posters are real renders of the wallpaper, so anything that changes the
    /// image — camera, rotation, surface type, grain — has to change the poster's
    /// filename. Keying them on the colours alone meant editing a preset's shape
    /// silently reused the previous file, and macOS kept showing it.
    public static func of<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
