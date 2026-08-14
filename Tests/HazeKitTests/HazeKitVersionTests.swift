import XCTest
@testable import HazeKit

/// The About page reads `HazeKit.version`. It used to be a literal that nobody
/// bumped, so the app showed 0.1.0 while shipping 0.1.4.
final class HazeKitVersionTests: XCTestCase {
    func testVersionComesFromTheBundleNotALiteral() {
        let bundle = Bundle(identifier: "com.adrbn.haze.HazeKit")
            ?? Bundle(for: LibraryManager.self)
        let stamped = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        XCTAssertEqual(HazeKit.version, stamped,
                       "version must track what the build stamped into the bundle")
    }

    func testVersionLooksLikeAVersion() {
        XCTAssertFalse(HazeKit.version.isEmpty)
        XCTAssertTrue(HazeKit.version.contains("."),
                      "got '\(HazeKit.version)' — the bundle lookup probably failed")
    }
}
