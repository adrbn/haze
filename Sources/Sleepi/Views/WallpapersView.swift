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

    enum LibraryCategory: String, CaseIterable, Identifiable {
        case all, favorites, videos, pictures, fluid, classic
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .favorites: return "Favorites"
            case .videos: return "Videos"
            case .pictures: return "Pictures"
            case .fluid: return "Fluid (3D)"
            case .classic: return "Classic (2D)"
            }
        }
        var systemImage: String? {
            switch self {
            case .favorites: return "star.fill"
            default: return nil
            }
        }
    }

    private var shown: [ContentItem] {
        switch category {
        case .all: return model.items
        case .favorites: return model.items.filter { model.isFavorite($0) }
        case .videos: return model.items.filter { $0.type == .video }
        case .pictures: return model.items.filter { $0.type == .image || $0.type == .animatedImage }
        case .fluid: return model.items.filter { $0.type == .shaderGradient }
        case .classic: return model.items.filter { $0.type == .gradient }
        }
    }

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

            categoryBar

            ScrollView {
                if shown.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: libraryGridColumns, spacing: 18) {
                        ForEach(shown) { item in
                            ContentCard(item: item,
                                        isSelected: model.settings.wallpaperItemID == item.id,
                                        tag: tag(for: item),
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

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryCategory.allCases) { cat in
                    Button { category = cat } label: {
                        HStack(spacing: 5) {
                            if let img = cat.systemImage { Image(systemName: img) }
                            Text(cat.title)
                        }
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(category == cat ? Color.accentColor : Color.white.opacity(0.08),
                                    in: Capsule())
                        .foregroundStyle(category == cat ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
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

    private func tag(for item: ContentItem) -> String? {
        switch item.type {
        case .shaderGradient: return "3D"
        case .gradient: return "2D"
        default: return nil
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
