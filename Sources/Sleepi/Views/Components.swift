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

/// A tappable library card: thumbnail + name + type badge, with a selection ring.
struct ContentCard: View {
    let item: ContentItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ContentThumbnailView(item: item)
                    .frame(maxWidth: .infinity)
                    .frame(height: 132)
                    .glassCard(cornerRadius: 16, selected: isSelected)
                    .overlay(alignment: .topLeading) { badge }
                    .overlay(alignment: .bottomTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(10)
                        }
                    }

                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var badge: some View {
        Image(systemName: item.type.symbol)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(7)
            .background(.black.opacity(0.45), in: Circle())
            .padding(8)
    }
}

let libraryGridColumns = [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 18)]
