import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SleepiKit

struct WallpapersView: View {
    @EnvironmentObject private var model: AppModel

    /// Imported media only — both 2D and 3D gradients live in their own tab.
    private var media: [ContentItem] { model.items.filter { !$0.type.isGradient } }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Wallpapers",
                       subtitle: "\(media.count) video\(media.count == 1 ? "" : "s"), GIF & image\(media.count == 1 ? "" : "s") · click to set your live desktop") {
                Button {
                    importPanel()
                } label: {
                    Label("Import", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if media.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: libraryGridColumns, spacing: 18) {
                        ForEach(media) { item in
                            ContentCard(item: item,
                                        isSelected: model.settings.wallpaperItemID == item.id,
                                        onRename: { model.rename(item, to: $0) }) {
                                model.setWallpaper(item)
                            }
                            .contextMenu { menu(for: item) }
                        }
                    }
                    .padding(24)
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for item: ContentItem) -> some View {
        Button("Set as Wallpaper") { model.setWallpaper(item) }
        Button("Use as Screensaver") { model.setScreensaver(item) }
        Divider()
        Button("Delete", role: .destructive) { model.deleteItem(item) }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No wallpapers yet")
                .font(.title3.weight(.semibold))
            Text("Import a video, GIF, or image — or create a gradient.")
                .foregroundStyle(.secondary)
            Button("Import Media…") { importPanel() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func importPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .image, .gif]
        panel.prompt = "Import"
        panel.message = "Choose videos, GIFs, or images to add to your library"
        if panel.runModal() == .OK {
            model.importFiles(panel.urls)
        }
    }
}
