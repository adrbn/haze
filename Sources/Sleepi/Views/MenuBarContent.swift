import SwiftUI
import AppKit
import SleepiKit

struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button("Open Sleepi…") {
            AppDelegate.shared?.showMainWindow()
        }
        .keyboardShortcut("o")

        Divider()

        Button(model.isPaused ? "Resume Wallpaper" : "Pause Wallpaper") {
            model.togglePause()
        }
        .keyboardShortcut("p")

        if !model.items.isEmpty {
            Menu("Switch Wallpaper") {
                ForEach(model.items) { item in
                    Button {
                        model.setWallpaper(item)
                    } label: {
                        if model.settings.wallpaperItemID == item.id {
                            Label(item.name, systemImage: "checkmark")
                        } else {
                            Text(item.name)
                        }
                    }
                }
            }
        }

        Divider()

        Button("Quit Sleepi") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
