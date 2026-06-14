import SwiftUI
import SleepiKit

@main
struct SleepiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("Sleepi", systemImage: "moon.stars.fill") {
            MenuBarContent()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.menu)
    }
}
