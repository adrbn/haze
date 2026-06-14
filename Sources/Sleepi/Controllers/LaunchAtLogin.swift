import Foundation
import ServiceManagement
import SleepiKit

/// Thin wrapper over `SMAppService` for launch-at-login (macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, let status) where status != .enabled:
                try SMAppService.mainApp.register()
            case (false, .enabled):
                try SMAppService.mainApp.unregister()
            default:
                break
            }
        } catch {
            Log.app.error("Launch-at-login toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
