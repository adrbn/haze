import XCTest
import CoreGraphics
@testable import SleepiKit

final class LibraryManagerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SleepiTests-\(UUID().uuidString)", isDirectory: true)
        ContentStore.overrideRootURL = tempRoot
        ContentStore.ensureDirectories()
    }

    override func tearDownWithError() throws {
        ContentStore.overrideRootURL = nil
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
    }

    private func makeTestPNG() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).png")
        let width = 8, height = 8
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = drawRed(ctx, width, height) else {
            throw XCTSkip("Could not create test image")
        }
        XCTAssertTrue(Thumbnailer.write(image, to: url))
        return url
    }

    private func drawRed(_ ctx: CGContext, _ w: Int, _ h: Int) -> CGImage? {
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    func testStartsEmpty() {
        let lib = LibraryManager()
        XCTAssertTrue(lib.items.isEmpty)
    }

    func testSeedDefaultsPopulatesGradients() {
        let lib = LibraryManager()
        lib.seedDefaultsIfNeeded()
        XCTAssertFalse(lib.items.isEmpty)
        XCTAssertEqual(lib.items.count, GradientPresets.all.count)
        XCTAssertTrue(lib.items.allSatisfy { $0.type == .gradient })
    }

    func testSeedIsIdempotent() {
        let lib = LibraryManager()
        lib.seedDefaultsIfNeeded()
        let count = lib.items.count
        lib.seedDefaultsIfNeeded()
        XCTAssertEqual(lib.items.count, count)
    }

    func testImportCopiesFileAndThumbnail() throws {
        let source = try makeTestPNG()
        defer { try? FileManager.default.removeItem(at: source) }

        let lib = LibraryManager()
        let item = try lib.importMedia(from: source, name: "Red")

        XCTAssertEqual(item.type, .image)
        XCTAssertEqual(item.name, "Red")
        XCTAssertEqual(lib.items.count, 1)
        XCTAssertNotNil(item.fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.fileURL!.path))
        XCTAssertNotNil(item.thumbnailURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.thumbnailURL!.path))
    }

    func testImportRejectsUnsupportedType() throws {
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("x.exe")
        try Data([0, 1, 2]).write(to: bad)
        defer { try? FileManager.default.removeItem(at: bad) }

        let lib = LibraryManager()
        XCTAssertThrowsError(try lib.importMedia(from: bad))
        XCTAssertTrue(lib.items.isEmpty)
    }

    func testRemoveDeletesBackingFiles() throws {
        let source = try makeTestPNG()
        defer { try? FileManager.default.removeItem(at: source) }

        let lib = LibraryManager()
        let item = try lib.importMedia(from: source)
        let fileURL = item.fileURL!
        let thumbURL = item.thumbnailURL!

        lib.remove(id: item.id)
        XCTAssertTrue(lib.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbURL.path))
    }

    func testManifestPersistsAcrossInstances() {
        let lib = LibraryManager()
        let item = lib.addGradient(GradientPresets.default.config, name: "Persisted")

        let reloaded = LibraryManager()
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(reloaded.item(id: item.id)?.name, "Persisted")
    }

    func testAddGradientStoresConfig() {
        let lib = LibraryManager()
        let config = GradientPresets.preset(id: "aurora")!.config
        let item = lib.addGradient(config, name: "Aurora")
        XCTAssertEqual(item.type, .gradient)
        XCTAssertEqual(item.gradient, config)
    }
}
