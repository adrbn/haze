import Combine
import Foundation
import AppKit
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
                                                  userDriverDelegate: self)
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
        comeToFront()
        controller.updater.checkForUpdates()
    }

    /// Haze runs as an `LSUIElement` agent, so it owns no Dock tile and is never
    /// the active app on its own. Sparkle's update window is an ordinary window:
    /// shown by a background app it opens *behind* everything, and because the
    /// flow is modal every click elsewhere just beeps — an invisible dialog
    /// holding the app hostage. Promote and activate before Sparkle presents
    /// anything, so its window has somewhere to come to the front of.
    private func comeToFront() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
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


// MARK: - Gentle reminders
//
// Sparkle warns that a background app scheduling its own checks "does not
// implement gentle reminders", and it is right: left alone it either pops a
// window the user never asked for or, for an agent, one they cannot see. Haze
// already announces an available update in its own UI — the menu-bar footer and
// the About page — so scheduled finds are handled there, and Sparkle only takes
// the screen when the user actually asked for it.
extension UpdaterController: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// A scheduled find is ours to show: the badge appears, nothing interrupts.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    /// When Sparkle does present — because the user asked — make sure there is a
    /// frontmost app for it to present into.
    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        Task { @MainActor in
            self.status = .available(version: update.displayVersionString)
            if state.userInitiated { self.comeToFront() }
        }
    }
}
