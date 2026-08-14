import SwiftUI
import AppKit
import HazeKit

/// The menu-bar panel. Replaces the old flat list of wallpaper names — which
/// grew unusable as the library did, with no way to tell one preset from
/// another — with a visual picker: what's playing pinned at the top, what you
/// last used one click away, then the rest as a filterable, searchable grid.
struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updater: UpdaterController

    @State private var category: LibraryCategory = .all
    @State private var query = ""

    private static let panelWidth: CGFloat = 340
    private static let recentCount = 4
    private static let gridColumns = 3
    private static let tileHeight: CGFloat = 62
    private static let gridRowSpacing: CGFloat = 10
    /// Thumbnail + gap + name label.
    private static let tileTotalHeight: CGFloat = tileHeight + 3 + 12
    /// Roughly three rows — enough to browse without the panel running off the
    /// screen on a laptop display.
    private static let maxGridHeight: CGFloat = 246

    /// Fit the grid to its rows, capped. Keeps a 4-preset library compact
    /// instead of padding it out with empty space.
    private var gridHeight: CGFloat {
        let rows = max(1, Int(ceil(Double(browseItems.count) / Double(Self.gridColumns))))
        let content = CGFloat(rows) * Self.tileTotalHeight
            + CGFloat(rows - 1) * Self.gridRowSpacing + 10
        return min(Self.maxGridHeight, content)
    }

    var body: some View {
        VStack(spacing: 0) {
            nowPlaying
            if model.currentSupportsSpeed { speedRow }
            if !recents.isEmpty {
                Divider().opacity(0.5)
                recentsRow
            }
            Divider().opacity(0.5)
            browse
            Divider().opacity(0.5)
            footer
        }
        .frame(width: Self.panelWidth)
    }

    // MARK: Now playing — always the top of the panel, whatever the filters say

    private var nowPlaying: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let item = model.currentWallpaper {
                    ContentThumbnailView(item: item)
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(height: 92)
            .clipped()

            // Scrim so the name stays legible over a bright wallpaper.
            LinearGradient(colors: [.clear, .black.opacity(0.8)],
                           startPoint: .center, endPoint: .bottom)
                .frame(height: 92)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 1) {
                Text("NOW PLAYING")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(.white.opacity(0.7))
                Text(model.currentWallpaper?.name ?? "No wallpaper")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 9)
        }
        .frame(height: 92)
        .overlay(alignment: .topTrailing) { pauseButton }
        .overlay(alignment: .topLeading) { typePill }
    }

    @ViewBuilder
    private var typePill: some View {
        if let type = model.currentWallpaper?.type {
            Label(type.displayName, systemImage: type.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.4), in: Capsule())
                .padding(9)
        }
    }

    private var pauseButton: some View {
        Button { model.togglePause() } label: {
            Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.black.opacity(0.4), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(9)
        .help(model.isPaused ? "Resume wallpaper" : "Pause wallpaper")
    }

    /// Live speed for the playing wallpaper — the one setting worth reaching for
    /// without opening the whole app.
    private var speedRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "speedometer")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Slider(value: Binding(get: { model.currentWallpaperSpeed },
                                  set: { model.setCurrentSpeed($0) }),
                   in: model.currentSpeedRange)
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: Recents

    private var recents: [ContentItem] { model.recentWallpapers(limit: Self.recentCount) }

    private var recentsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Recent")
            HStack(spacing: 8) {
                ForEach(recents) { item in
                    WallpaperTile(item: item, isCurrent: false, width: 72, height: 46,
                                  showsName: false) { model.setWallpaper(item) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 9)
        .padding(.bottom, 11)
    }

    // MARK: Browse

    /// Category + search. A non-empty search deliberately spans the whole
    /// library: hunting for a name you remember shouldn't need the right filter
    /// selected first.
    private var browseItems: [ContentItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return model.items(in: category) }
        return model.items.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var browse: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                sectionLabel("Library").padding(.horizontal, 0)
                Spacer(minLength: 0)
                searchField
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)

            categoryPills

            if browseItems.isEmpty {
                Text(query.isEmpty ? "Nothing here yet" : "No match for “\(query)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 22)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: Self.gridColumns),
                              spacing: Self.gridRowSpacing) {
                        ForEach(browseItems) { item in
                            WallpaperTile(item: item,
                                          isCurrent: item.id == model.settings.wallpaperItemID,
                                          width: nil, height: Self.tileHeight, showsName: true) {
                                model.setWallpaper(item)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                // A definite height, not a max: the panel sizes itself to its
                // content, and a ScrollView asked only for a maximum collapses
                // to nothing. Short libraries shrink the panel, long ones scroll.
                .frame(height: gridHeight)
                // Always open showing the first row — without this the grid can
                // come up mid-list once the thumbnails finish loading in.
                .defaultScrollAnchor(.top)
            }
        }
        .padding(.bottom, 4)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 96)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.07), in: Capsule())
    }

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LibraryCategory.allCases) { cat in
                    Button { category = cat } label: {
                        HStack(spacing: 3) {
                            if let img = cat.systemImage { Image(systemName: img) }
                            if let label = cat.compactTitle { Text(label) }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(category == cat ? Color.accentColor : Color.primary.opacity(0.07),
                                    in: Capsule())
                        .foregroundStyle(category == cat ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .opacity(query.isEmpty ? 1 : 0.4)
        .disabled(!query.isEmpty)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.9)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            FooterButton(title: "Open Haze…", systemImage: "macwindow") {
                AppDelegate.shared?.showMainWindow()
            }
            Spacer(minLength: 0)
            // An available update is announced where the app actually lives.
            // Buried in a window nobody opens, the news never arrives.
            FooterButton(title: updater.status.isAvailable ? "Update ready" : "Updates",
                         systemImage: updater.status.isAvailable
                            ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath",
                         highlighted: updater.status.isAvailable) {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
            FooterButton(title: "Quit", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}

/// One wallpaper in the panel: preview, selection ring, optional name.
/// `width: nil` lets the grid size it.
private struct WallpaperTile: View {
    let item: ContentItem
    let isCurrent: Bool
    let width: CGFloat?
    let height: CGFloat
    let showsName: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 3) {
            Button(action: action) {
                ContentThumbnailView(item: item)
                    .frame(width: width, height: height)
                    .frame(maxWidth: width == nil ? .infinity : nil)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isCurrent ? Color.accentColor
                                          : Color.primary.opacity(hovering ? 0.35 : 0.12),
                                          lineWidth: isCurrent ? 2 : 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isCurrent {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(3)
                        }
                    }
            }
            .buttonStyle(.plain)

            if showsName {
                Text(item.name)
                    .font(.system(size: 9))
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .onHover { hovering = $0 }
        .help(item.name)
    }
}

/// A compact, menu-like row action with a hover highlight (the panel is a
/// window, so it gets none of `NSMenu`'s built-in highlighting).
private struct FooterButton: View {
    let title: String
    let systemImage: String
    var highlighted = false
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: highlighted ? .semibold : .medium))
                .foregroundStyle(highlighted ? Color.accentColor : Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(highlighted
                            ? Color.accentColor.opacity(0.15)
                            : (hovering && isEnabled ? Color.primary.opacity(0.09) : .clear),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
