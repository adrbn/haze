import Combine
import Foundation
import Sparkle

/// Owns Sparkle's updater and exposes a tiny surface for the menu bar:
/// `checkForUpdates()` plus a published `canCheckForUpdates` that disables the
/// menu item while a check is already in flight.
///
/// Everything the user sees — the "update available" prompt, the HTML changelog,
/// the "Install and Relaunch" button, and the scheduled background checks — is
/// Sparkle's standard user driver. We add no custom UI. Cadence and the
/// automatic-check policy come from Info.plist (`SUScheduledCheckInterval`,
/// `SUEnableAutomaticChecks`); update authenticity comes from the EdDSA
/// `SUPublicEDKey`, so ad-hoc-signed builds still update safely.
@MainActor
final class UpdaterController: ObservableObject {
    /// Drives the enabled state of the "Check for Updates…" menu item.
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true → Sparkle starts its scheduled background checks
        // right away. No delegates needed for the standard ad-hoc flow.
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Manual check — shows Sparkle's UI even when the app is already up to date.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
