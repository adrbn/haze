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

    private var shaders: [ContentItem] { model.items.filter { $0.type == .shaderGradient } }
    private var classics: [ContentItem] { model.items.filter { $0.type == .gradient } }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Gradients",
                       subtitle: "Animated gradients — fluid 3D or classic 2D") {
                Menu {
                    Button("Fluid Gradient (3D)") { editing = .newShader }
                    Button("Classic Gradient (2D)") { editing = .newClassic }
                } label: {
                    Label("New Gradient", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.large)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !shaders.isEmpty {
                        sectionHeader("Fluid (3D)",
                                      "Lit, flowing 3D surfaces")
                        grid(shaders, tag: "3D")
                    }
                    if !classics.isEmpty {
                        sectionHeader("Classic 2D",
                                      "Flat animated colour fields — lighter on the GPU")
                        grid(classics, tag: "2D")
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .sheet(item: $editing) { target in
            editor(for: target).environmentObject(model)
        }
    }

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 10)
    }

    private func grid(_ items: [ContentItem], tag: String) -> some View {
        LazyVGrid(columns: libraryGridColumns, spacing: 18) {
            ForEach(items) { item in
                ContentCard(item: item,
                            isSelected: model.settings.wallpaperItemID == item.id,
                            tag: tag,
                            onRename: { model.rename(item, to: $0) }) {
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
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func editor(for target: EditingTarget) -> some View {
        switch target {
        case .newShader:
            ShaderGradientEditorView(config: ShaderGradientPresets.default.config,
                                     name: "My Fluid Gradient", existing: nil)
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
