import Foundation

/// Tiny atomic JSON persistence helper used for the library manifest and
/// settings. Reads are best-effort (return `nil` on any failure); writes are
/// atomic so a crash mid-write never corrupts the file.
public enum JSONStore {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Log.library.error("Decode failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    public static func save<T: Encodable>(_ value: T, to url: URL) -> Bool {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            Log.library.error("Encode/write failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
