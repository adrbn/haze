import SwiftUI
import SleepiKit

struct GradientsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: EditingTarget?

    enum EditingTarget: Identifiable {
        case newShader
        case newClassic
        case existing(ContentItem)
        var id: String {
            switch self {
            case .newShader: return "new-shader"
            case .newClassic: return "new-classic"
            case .existing(let item): return item.id.uuidString
            }
        }
    }

    private var gradients: [ContentItem] { model.items.filter { $0.type.isGradient } }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Gradients",
                       subtitle: "Animated gradients — 3D ShaderGradient or classic 2D") {
                Menu {
                    Button("3D ShaderGradient") { editing = .newShader }
                    Button("Classic 2D") { editing = .newClassic }
                } label: {
                    Label("New Gradient", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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
        case .newShader:
            ShaderGradientEditorView(config: ShaderGradientPresets.default.config,
                                     name: "My ShaderGradient", existing: nil)
        case .newClassic:
            GradientEditorView(config: GradientPresets.default.config,
                               name: "My Gradient", existing: nil)
        case .existing(let item):
            if item.type == .shaderGradient {
                ShaderGradientEditorView(config: item.shaderGradient ?? ShaderGradientPresets.default.config,
                                         name: item.name, existing: item)
            } else {
                GradientEditorView(config: item.gradient ?? GradientPresets.default.config,
                                   name: item.name, existing: item)
            }
        }
    }

    private func duplicate(_ item: ContentItem) {
        if let sg = item.shaderGradient {
            model.addShaderGradient(sg, name: item.name + " copy")
        } else if let g = item.gradient {
            model.addGradient(g, name: item.name + " copy")
        }
    }
}
