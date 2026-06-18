import Foundation

/// Tiny atomic JSON persistence helper used for the library manifest and
/// settings. Reads are best-effort (return `nil` on any failure); writes are
/// atomic so a crash mid-write never corrupts the file.
///
/// Coders are created per call (cheap) rather than shared, so `save`/`load` are
/// safe to invoke from any thread — including the background import path.
public enum JSONStore {
    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// A freshly-configured encoder/decoder. Exposed for tests and callers that
    /// want the project's canonical formatting.
    public static var encoder: JSONEncoder { makeEncoder() }
    public static var decoder: JSONDecoder { makeDecoder() }

    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try makeDecoder().decode(T.self, from: data)
        } catch {
            Log.library.error("Decode failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    public static func save<T: Encodable>(_ value: T, to url: URL) -> Bool {
        do {
            let data = try makeEncoder().encode(value)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            Log.library.error("Encode/write failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
