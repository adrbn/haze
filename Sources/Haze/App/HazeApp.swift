import SwiftUI
import HazeKit

@main
struct HazeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        MenuBarExtra("Haze", systemImage: "sparkles") {
            MenuBarContent()
                .environmentObject(model)
                .environmentObject(updater)
        }
        .menuBarExtraStyle(.menu)
    }
}
