import XCTest
@testable import SleepiKit

final class ContentTypeTests: XCTestCase {
    func testInferVideo() {
        XCTAssertEqual(ContentType.infer(from: URL(fileURLWithPath: "/x/a.mp4")), .video)
        XCTAssertEqual(ContentType.infer(from: URL(fileURLWithPath: "/x/a.MOV")), .video)
        XCTAssertEqual(ContentType.infer(from: URL(fileURLWithPath: "/x/a.m4v")), .video)
    }

    func testInferAnimated() {
        XCTAssertEqual(ContentType.infer(from: URL(fileURLWithPath: "/x/a.gif")), .animatedImage)
        XCTAssertEqual(ContentType.infer(from: URL(fileURLWithPath: "/x/a.APNG")), .animatedImage)
    }

    func testInferImage() {
        XCTAssertEqual(ContentType.infer(from: URL(fileURLWithPath: "/x/a.png")), .image)
        XCTAssertEqual(ContentType.infer(from: URL(fileURLWithPath: "/x/a.jpeg")), .image)
        XCTAssertEqual(ContentType.infer(from: URL(fileURLWithPath: "/x/a.heic")), .image)
    }

    func testInferUnknownFallsBackToVideo() {
        XCTAssertEqual(ContentType.infer(from: URL(fileURLWithPath: "/x/a.xyz")), .video)
    }

    func testImportableExtensionsCoverCommonFormats() {
        let exts = Set(ContentType.importableExtensions)
        XCTAssertTrue(exts.contains("mp4"))
        XCTAssertTrue(exts.contains("gif"))
        XCTAssertTrue(exts.contains("png"))
    }
}
