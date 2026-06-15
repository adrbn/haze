import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SleepiKit

/// The library: imported media (Videos, Pictures) and gradients (Fluid 3D,
/// Classic 2D) in one place. Click any card to set it as the live wallpaper.
struct WallpapersView: View {
    @EnvironmentObject private var model: AppModel

    private var videos: [ContentItem] { model.items.filter { $0.type == .video } }
    private var pictures: [ContentItem] { model.items.filter { $0.type == .image || $0.type == .animatedImage } }
    private var fluid: [ContentItem] { model.items.filter { $0.type == .shaderGradient } }
    private var classic: [ContentItem] { model.items.filter { $0.type == .gradient } }

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

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("Videos", "Looping video wallpapers", videos,
                            tag: nil, emptyHint: "Import a video (.mp4 / .mov) to add one.")
                    section("Pictures", "Stills & animated GIFs", pictures,
                            tag: nil, emptyHint: "Import an image or GIF to add one.")
                    section("Fluid (3D)", "Lit, flowing 3D gradients", fluid, tag: "3D")
                    section("Classic (2D)", "Flat animated gradients — lighter on the GPU", classic, tag: "2D")
                }
                .padding(.vertical, 10)
            }
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
    private func section(_ title: String, _ subtitle: String, _ items: [ContentItem],
                         tag: String?, emptyHint: String? = nil) -> some View {
        if !items.isEmpty {
            sectionHeader(title, subtitle)
            grid(items, tag: tag)
        } else if let emptyHint {
            sectionHeader(title, subtitle)
            Text(emptyHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
        }
    }

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private func grid(_ items: [ContentItem], tag: String?) -> some View {
        LazyVGrid(columns: libraryGridColumns, spacing: 18) {
            ForEach(items) { item in
                ContentCard(item: item,
                            isSelected: model.settings.wallpaperItemID == item.id,
                            tag: tag,
                            onRename: { model.rename(item, to: $0) }) {
                    model.setWallpaper(item)
                }
                .contextMenu { menu(for: item) }
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func menu(for item: ContentItem) -> some View {
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
