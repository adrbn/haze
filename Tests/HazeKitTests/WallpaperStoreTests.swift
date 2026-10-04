import XCTest
@testable import HazeKit

/// macOS keeps one desktop picture *per Space*. `setDesktopImageURL` only writes
/// the Space that happens to be active, so every other Space keeps whichever
/// poster was current the last time it was frontmost — which is what made the
/// menu bar draw its pale legibility backdrop over a dark wallpaper.
final class WallpaperStoreTests: XCTestCase {
    private let posters = URL(fileURLWithPath: "/Users/test/Library/Application Support/Haze/Posters", isDirectory: true)
    private var current: URL { posters.appendingPathComponent("NEW-abc.jpg") }
    private var stale: URL { posters.appendingPathComponent("OLD-xyz.jpg") }
    private let userPicture = URL(fileURLWithPath: "/Users/test/Pictures/church.jpg")

    // MARK: Fixtures

    private func imageContent(_ url: URL) -> [String: Any] {
        let configuration = try! PropertyListSerialization.data(
            fromPropertyList: ["url": ["relative": url.absoluteString]],
            format: .binary, options: 0)
        return ["Choices": [["Provider": WallpaperStore.imageProvider, "Configuration": configuration]]]
    }

    private func colorContent() -> [String: Any] {
        ["Choices": [["Provider": "com.apple.wallpaper.choice.color"]]]
    }

    /// A store shaped like the real `Index.plist`: a system default plus one
    /// entry per Space, and an `Idle` (screen saver) sibling that must be left alone.
    private func store(desktops: [String: [String: Any]], idle: [String: Any]? = nil) -> [String: Any] {
        var spaces: [String: Any] = [:]
        for (name, content) in desktops {
            var space: [String: Any] = ["Default": ["Desktop": ["Content": content]]]
            if let idle { space["Idle"] = ["Content": idle] }
            spaces[name] = space
        }
        return ["Spaces": spaces]
    }

    // MARK: Reading back

    private func desktopURL(_ root: Any, space: String) -> URL? {
        guard let dict = root as? [String: Any],
              let spaces = dict["Spaces"] as? [String: Any],
              let one = spaces[space] as? [String: Any],
              let def = one["Default"] as? [String: Any],
              let desktop = def["Desktop"] as? [String: Any],
              let content = desktop["Content"] as? [String: Any] else { return nil }
        return WallpaperStore.imageURL(content)
    }

    private func idleProvider(_ root: Any, space: String) -> String? {
        guard let dict = root as? [String: Any],
              let spaces = dict["Spaces"] as? [String: Any],
              let one = spaces[space] as? [String: Any],
              let idle = one["Idle"] as? [String: Any],
              let content = idle["Content"] as? [String: Any] else { return nil }
        return WallpaperStore.provider(content)
    }

    private func heal(_ root: Any) -> WallpaperStore.HealOutcome {
        WallpaperStore.heal(root, posterURL: current, posterDirectory: posters)
    }

    // MARK: Tests

    /// The regression this whole change is about: a Space still pointing at one of
    /// our own older posters must be brought up to date.
    func testRewritesStaleHazePoster() {
        let root = store(desktops: ["a": imageContent(current), "b": imageContent(stale)])
        guard case let .healed(healed, desktops) = heal(root) else {
            return XCTFail("expected the stale Space to be healed")
        }
        XCTAssertEqual(desktops, 1)
        XCTAssertEqual(desktopURL(healed, space: "b"), current)
        XCTAssertEqual(desktopURL(healed, space: "a"), current)
    }

    /// Pre-existing behaviour: a Space whose desktop is a colour (or any non-image
    /// choice) can't be reached by `setDesktopImageURL` at all.
    func testRewritesNonImageDesktop() {
        let root = store(desktops: ["a": imageContent(current), "b": colorContent()])
        guard case let .healed(healed, desktops) = heal(root) else {
            return XCTFail("expected the colour Space to be healed")
        }
        XCTAssertEqual(desktops, 1)
        XCTAssertEqual(desktopURL(healed, space: "b"), current)
    }

    /// The user's own wallpaper is theirs. We only ever take over pictures we wrote —
    /// even while healing the Spaces around them.
    func testLeavesUsersOwnPictureAlone() {
        let root = store(desktops: ["a": imageContent(current),
                                    "b": imageContent(userPicture),
                                    "c": colorContent()])
        guard case let .healed(healed, desktops) = heal(root) else {
            return XCTFail("expected the colour Space to be healed")
        }
        XCTAssertEqual(desktops, 1, "only the colour Space — not the user's picture")
        XCTAssertEqual(desktopURL(healed, space: "b"), userPicture)
        XCTAssertEqual(desktopURL(healed, space: "c"), current)
    }

    /// A store holding only the user's own pictures is left completely alone.
    func testUsersOwnPicturesAloneMeanNothingToDo() {
        let root = store(desktops: ["a": imageContent(current), "b": imageContent(userPicture)])
        guard case .upToDate = heal(root) else {
            return XCTFail("expected upToDate — nothing of ours is stale")
        }
    }

    /// Nothing to do → no write, no WallpaperAgent reload, no wallpaper flash.
    func testUpToDateWhenEveryPosterAlreadyCurrent() {
        let root = store(desktops: ["a": imageContent(current), "b": imageContent(current)])
        guard case .upToDate = heal(root) else {
            return XCTFail("expected upToDate when every desktop we own already matches")
        }
    }

    /// `setDesktopImageURL` is an async hop into WallpaperAgent: until it lands,
    /// the store has no entry to copy Apple's exact format from.
    func testNotReadyBeforeTheNewPosterAppears() {
        let root = store(desktops: ["a": imageContent(stale), "b": colorContent()])
        guard case .notReady = heal(root) else {
            return XCTFail("expected notReady while no entry points at the new poster")
        }
    }

    /// Screen-saver entries live next to desktops in the same tree.
    func testLeavesIdleEntriesAlone() {
        let root = store(desktops: ["a": imageContent(current), "b": colorContent()],
                         idle: colorContent())
        guard case let .healed(healed, _) = heal(root) else {
            return XCTFail("expected the colour Space to be healed")
        }
        XCTAssertEqual(idleProvider(healed, space: "b"), "com.apple.wallpaper.choice.color")
    }

    func testCountsEveryHealedDesktop() {
        let root = store(desktops: [
            "a": imageContent(current),
            "b": imageContent(stale),
            "c": imageContent(stale),
            "d": colorContent(),
            "e": imageContent(userPicture),
        ])
        guard case let .healed(_, desktops) = heal(root) else { return XCTFail("expected a heal") }
        XCTAssertEqual(desktops, 3)
    }

    func testPosterDirectoryMembershipIsExact() {
        XCTAssertTrue(WallpaperStore.isPoster(current, in: posters))
        XCTAssertFalse(WallpaperStore.isPoster(userPicture, in: posters))
        // A nested path that merely starts with the posters path is not a poster.
        let nested = posters.appendingPathComponent("sub/deep.jpg")
        XCTAssertFalse(WallpaperStore.isPoster(nested, in: posters))
    }
}
