import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SleepiKit

/// The library: imported media and gradients in one place, filtered by a
/// horizontal category bar (All / Favorites / Videos / Pictures / Fluid 3D /
/// Classic 2D). Click any card to set it as the live wallpaper.
struct WallpapersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var category: LibraryCategory = .all

    private var shown: [ContentItem] { model.items(in: category) }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Wallpapers",
                       subtitle: "Videos, images & gradients — click to set your live desktop") {
                HStack(spacing: 10) {
                    newGradientMenu
                    Button { importPanel() } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            CategoryBar(selection: $category)

            ScrollView {
                if shown.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: libraryGridColumns, spacing: 18) {
                        ForEach(shown) { item in
                            ContentCard(item: item,
                                        isSelected: model.settings.wallpaperItemID == item.id,
                                        tag: item.type.shortTag,
                                        isFavorite: model.isFavorite(item),
                                        onToggleFavorite: { model.toggleFavorite(item) },
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: category == .favorites ? "star" : "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(emptyMessage).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var emptyMessage: String {
        switch category {
        case .favorites: return "No favorites yet — tap the ★ on any wallpaper."
        case .videos: return "No videos yet — use Import to add .mp4 / .mov files."
        case .pictures: return "No pictures yet — use Import to add images or GIFs."
        default: return "Nothing here yet."
        }
    }

    private var newGradientMenu: some View {
        Menu {
            Button { AppDelegate.shared?.showGradientEditor(.newFluid) } label: {
                Label("Fluid Gradient (3D)", systemImage: "cube.fill")
            }
            Button { AppDelegate.shared?.showGradientEditor(.newClassic) } label: {
                Label("Classic Gradient (2D)", systemImage: "circle.hexagongrid.fill")
            }
        } label: {
            Label("New Gradient", systemImage: "plus")
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .fixedSize()
    }

    @ViewBuilder
    private func menu(for item: ContentItem) -> some View {
        Button(model.isFavorite(item) ? "Remove from Favorites" : "Add to Favorites") {
            model.toggleFavorite(item)
        }
        Button("Set as Wallpaper") { model.setWallpaper(item) }
        Button("Use as Screensaver") { model.setScreensaver(item) }
        if item.type.isGradient {
            Button("Edit…") { AppDelegate.shared?.showGradientEditor(.existing(item)) }
            Button("Duplicate") { duplicate(item) }
        }
        Divider()
        Button("Delete", role: .destructive) { model.deleteItem(item) }
    }

    private func duplicate(_ item: ContentItem) {
        if let sg = item.shaderGradient {
            model.addShaderGradient(sg, name: item.name + " copy")
        } else if let g = item.gradient {
            model.addGradient(g, name: item.name + " copy")
        }
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
