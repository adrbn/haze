import SwiftUI
import SleepiKit

/// Standard page header with a title, optional subtitle, and trailing actions.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

/// A tappable library card: thumbnail + name + type badge, with a selection
/// ring. Double-clicking the name renames the item (when `onRename` is set).
struct ContentCard: View {
    let item: ContentItem
    let isSelected: Bool
    var tag: String? = nil
    var isFavorite: Bool = false
    var onToggleFavorite: (() -> Void)? = nil
    var onRename: ((String) -> Void)? = nil
    let action: () -> Void

    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var hovering = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                ContentThumbnailView(item: item)
                    .frame(maxWidth: .infinity)
                    .frame(height: 132)
                    .glassCard(cornerRadius: 16, selected: isSelected)
                    .overlay(alignment: .topLeading) { badge }
                    .overlay(alignment: .topTrailing) { tagPill }
                    .overlay(alignment: .bottomLeading) { favoriteButton }
                    .overlay(alignment: .bottomTrailing) { selectedCheck }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }

            nameView
        }
    }

    @ViewBuilder
    private var favoriteButton: some View {
        if onToggleFavorite != nil, hovering || isFavorite {
            Button { onToggleFavorite?() } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isFavorite ? Color.yellow : .white)
                    .padding(7)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(8)
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
    }

    @ViewBuilder
    private var nameView: some View {
        if isRenaming {
            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
                .focused($nameFocused)
                .onSubmit { commitRename() }
                .onExitCommand { isRenaming = false }
                .onChange(of: nameFocused) { if !nameFocused { commitRename() } }
        } else {
            Text(item.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    guard onRename != nil else { return }
                    draftName = item.name
                    isRenaming = true
                    nameFocused = true
                }
                .help(onRename != nil ? "Double-click to rename" : "")
        }
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != item.name { onRename?(trimmed) }
    }

    private var badge: some View {
        Image(systemName: item.type.symbol)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(7)
            .background(.black.opacity(0.45), in: Circle())
            .padding(8)
    }

    @ViewBuilder
    private var tagPill: some View {
        if let tag {
            Text(tag)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(8)
        }
    }

    @ViewBuilder
    private var selectedCheck: some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.white, Color.accentColor)
                .padding(10)
        }
    }
}

let libraryGridColumns = [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 18)]

/// Library filter categories, shared by the Wallpapers and Screensaver pickers.
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

    var systemImage: String? { self == .favorites ? "star.fill" : nil }

    func matches(_ item: ContentItem, isFavorite: Bool) -> Bool {
        switch self {
        // "All" hides Classic 2D gradients to keep the main view clean — they
        // stay one click away under the "Classic (2D)" pill.
        case .all: return item.type != .gradient
        case .favorites: return isFavorite
        case .videos: return item.type == .video
        case .pictures: return item.type == .image || item.type == .animatedImage
        case .fluid: return item.type == .shaderGradient
        case .classic: return item.type == .gradient
        }
    }
}

/// Horizontal pill bar for picking a `LibraryCategory`.
struct CategoryBar: View {
    @Binding var selection: LibraryCategory

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryCategory.allCases) { cat in
                    Button { selection = cat } label: {
                        HStack(spacing: 5) {
                            if let img = cat.systemImage { Image(systemName: img) }
                            Text(cat.title)
                        }
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(selection == cat ? Color.accentColor : Color.white.opacity(0.08),
                                    in: Capsule())
                        .foregroundStyle(selection == cat ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }
}
