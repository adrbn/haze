import SwiftUI
import AppKit
import HazeKit

struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel

    /// Type groups for the "Switch Wallpaper" submenu, in display order. Together
    /// they cover every item exactly once (each item has one content type).
    private static let menuCategories: [LibraryCategory] = [.videos, .pictures, .fluid, .classic]

    var body: some View {
        Button("Open Haze…") {
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
                // Grouped by category (Videos, Pictures, Fluid 3D, Classic 2D) so a
                // long library is browseable instead of one flat list.
                ForEach(Self.menuCategories) { category in
                    let items = model.items(in: category)
                    if !items.isEmpty {
                        Section(category.title) {
                            ForEach(items) { item in
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
                }
            }
        }

        Divider()

        Button("Quit Haze") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
