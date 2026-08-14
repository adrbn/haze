import Combine
import Foundation
import Sparkle

/// What the app currently knows about updates.
enum UpdateStatus: Equatable {
    case unknown
    case checking
    case upToDate
    case available(version: String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

/// Owns Sparkle's updater and publishes what it finds.
///
/// Everything the user sees during an actual update — the prompt, the HTML
/// changelog, "Install and Relaunch", the scheduled background checks — is
/// Sparkle's standard user driver, unchanged. What this adds is knowing quietly
/// whether an update exists, so the app can *say so* instead of offering a
/// button that only reveals the answer once you press it.
/// `checkForUpdateInformation()` asks the feed without putting anything on
/// screen; the delegate callbacks below record the answer.
///
/// Cadence and the automatic-check policy come from Info.plist
/// (`SUScheduledCheckInterval`, `SUEnableAutomaticChecks`). Update authenticity
/// comes from the EdDSA `SUPublicEDKey` — and, in practice, from the installed
/// copy carrying the same Developer ID, since Sparkle refuses an update whose
/// signature does not match the app's.
@MainActor
final class UpdaterController: NSObject, ObservableObject, SPUUpdaterDelegate {
    /// Sparkle expects a single updater per process, and both the menu bar and
    /// the About page drive it — so it is shared rather than owned by whichever
    /// view happened to be built first.
    static let shared = UpdaterController()

    /// Drives the enabled state of the "Check for Updates…" controls.
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var status: UpdateStatus = .unknown
    @Published private(set) var lastCheck: Date?

    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        // startingUpdater: true → Sparkle runs its scheduled background checks.
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: self,
                                                  userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        lastCheck = controller.updater.lastUpdateCheckDate

        // One silent check a few seconds after launch, so the About page can
        // show the answer rather than hide it behind a button. Delayed so it
        // never competes with the window server settling at startup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.checkQuietly()
        }
    }

    /// Ask the feed without showing any UI.
    func checkQuietly() {
        guard canCheckForUpdates else { return }
        status = .checking
        controller.updater.checkForUpdateInformation()
    }

    /// Manual check — shows Sparkle's UI even when already up to date, and is
    /// also how an offered update actually gets installed.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            self.status = .available(version: version)
            self.lastCheck = Date()
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.status = .upToDate
            self.lastCheck = Date()
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // A failed background check is not worth a banner: the manual button
        // still works and reports properly when the user asks explicitly.
        Task { @MainActor in
            if self.status == .checking { self.status = .unknown }
        }
    }
}
