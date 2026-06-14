import SwiftUI
import SleepiKit

struct GradientEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var config: GradientConfig
    @State private var name: String
    private let existing: ContentItem?

    init(config: GradientConfig, name: String, existing: ContentItem?) {
        _config = State(initialValue: config)
        _name = State(initialValue: name)
        self.existing = existing
    }

    var body: some View {
        VStack(spacing: 0) {
            GradientMetalPreview(config: config)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.headline)
                        TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Style").font(.headline)
                        Picker("Style", selection: $config.style) {
                            ForEach(GradientStyle.allCases, id: \.self) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    colorsSection

                    slider("Speed", $config.speed, 0...2)
                    slider("Warp", $config.warp, 0...2)
                    slider("Grain", $config.grain, 0...0.5)
                    slider("Brightness", $config.brightness, 0.6...1.4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Frame rate").font(.headline)
                        Picker("FPS", selection: $config.fps) {
                            Text("24").tag(24)
                            Text("30").tag(30)
                            Text("60").tag(60)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save to Library") { save(setAsWallpaper: false) }
                Button("Set as Wallpaper") { save(setAsWallpaper: true) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 520, height: 760)
    }

    private var colorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Colors").font(.headline)
                Spacer()
                Button { addColor() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .disabled(config.colors.count >= 6)
            }
            ForEach(config.colors.indices, id: \.self) { index in
                HStack(spacing: 10) {
                    ColorPicker("", selection: colorBinding(index), supportsOpacity: false)
                        .labelsHidden()
                    Text(hexString(config.colors[index]))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { removeColor(index) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .disabled(config.colors.count <= 2)
                }
            }
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.headline)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { config.colors[index].swiftUIColor },
            set: { config.colors[index] = RGBAColor($0) })
    }

    private func hexString(_ color: RGBAColor) -> String {
        String(format: "#%02X%02X%02X",
               Int((color.r * 255).rounded()),
               Int((color.g * 255).rounded()),
               Int((color.b * 255).rounded()))
    }

    private func addColor() {
        guard config.colors.count < 6 else { return }
        config.colors.append(config.colors.last ?? RGBAColor(r: 1, g: 1, b: 1))
    }

    private func removeColor(_ index: Int) {
        guard config.colors.count > 2, config.colors.indices.contains(index) else { return }
        config.colors.remove(at: index)
    }

    private func save(setAsWallpaper: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Gradient" : trimmed
        let item: ContentItem
        if let existing {
            var updated = existing
            updated.name = finalName
            updated.gradient = config
            model.updateItem(updated)
            item = updated
        } else {
            item = model.addGradient(config, name: finalName)
        }
        if setAsWallpaper { model.setWallpaper(item) }
        dismiss()
    }
}
