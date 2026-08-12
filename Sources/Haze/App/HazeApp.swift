import SwiftUI
import HazeKit

@main
struct HazeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        // `.window`, not `.menu`: an NSMenu can't show wallpaper previews, and a
        // list of bare names was unreadable past a handful of presets.
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(model)
                .environmentObject(updater)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}
