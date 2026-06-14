import SwiftUI
import SleepiKit

struct GradientsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: EditingTarget?

    enum EditingTarget: Identifiable {
        case new
        case existing(ContentItem)
        var id: String {
            switch self {
            case .new: return "new"
            case .existing(let item): return item.id.uuidString
            }
        }
    }

    private var gradients: [ContentItem] { model.items(ofType: .gradient) }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Gradients",
                       subtitle: "Animated Metal gradients inspired by shadergradient") {
                Button { editing = .new } label: {
                    Label("New Gradient", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            ScrollView {
                LazyVGrid(columns: libraryGridColumns, spacing: 18) {
                    ForEach(gradients) { item in
                        ContentCard(item: item,
                                    isSelected: model.settings.wallpaperItemID == item.id) {
                            model.setWallpaper(item)
                        }
                        .contextMenu {
                            Button("Set as Wallpaper") { model.setWallpaper(item) }
                            Button("Use as Screensaver") { model.setScreensaver(item) }
                            Button("Edit…") { editing = .existing(item) }
                            Button("Duplicate") { duplicate(item) }
                            Divider()
                            Button("Delete", role: .destructive) { model.deleteItem(item) }
                        }
                    }
                }
                .padding(24)
            }
        }
        .sheet(item: $editing) { target in
            editor(for: target).environmentObject(model)
        }
    }

    @ViewBuilder
    private func editor(for target: EditingTarget) -> some View {
        switch target {
        case .new:
            GradientEditorView(config: GradientPresets.default.config,
                               name: "My Gradient", existing: nil)
        case .existing(let item):
            GradientEditorView(config: item.gradient ?? GradientPresets.default.config,
                               name: item.name, existing: item)
        }
    }

    private func duplicate(_ item: ContentItem) {
        guard let config = item.gradient else { return }
        model.addGradient(config, name: item.name + " copy")
    }
}
