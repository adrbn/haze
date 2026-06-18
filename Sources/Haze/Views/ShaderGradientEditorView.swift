import SwiftUI
import HazeKit

struct ShaderGradientEditorView: View {
    @EnvironmentObject private var model: AppModel

    @State private var config: ShaderGradientConfig
    @State private var name: String
    private let existing: ContentItem?
    private let onClose: () -> Void

    init(config: ShaderGradientConfig, name: String, existing: ContentItem?, onClose: @escaping () -> Void) {
        _config = State(initialValue: config)
        _name = State(initialValue: name)
        self.existing = existing
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            ShaderGradientMetalPreview(config: config)
                .frame(height: 250)
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
                        Text("Type").font(.headline)
                        Picker("Type", selection: $config.type) {
                            ForEach(GradientType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Colors").font(.headline)
                        ForEach(0..<3, id: \.self) { i in
                            HStack(spacing: 10) {
                                ColorPicker("", selection: colorBinding(i), supportsOpacity: false)
                                    .labelsHidden()
                                Text(hexString(config.colors[safe: i] ?? RGBAColor(r: 0, g: 0, b: 0)))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }

                    slider("Speed", $config.speed, 0...1)
                    slider("Density", $config.density, 0...3)
                    slider("Frequency", $config.frequency, 0...10)
                    slider("Strength", $config.strength, 0...8)
                    slider("Amplitude", $config.amplitude, 0...3)
                    slider("Grain", $config.grain, 0...1)
                    slider("Blur", $config.blur, 0...1)
                    slider("Brightness", $config.brightness, 0.6...2)
                    slider("Roll", $config.rotationZ, 0...360)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Frame rate").font(.headline)
                        Picker("FPS", selection: $config.fps) {
                            Text("10").tag(10)
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
                Button("Cancel") { onClose() }
                Spacer()
                Button("Save to Library") { save(setAsWallpaper: false) }
                Button("Set as Wallpaper") { save(setAsWallpaper: true) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 540, height: 820)
        .onChange(of: config) { liveApply() }
    }

    /// While editing the wallpaper that's currently playing, push slider changes
    /// (speed, colours, etc.) to the live desktop in real time.
    private func liveApply() {
        guard let existing else { return }
        var updated = existing
        updated.shaderGradient = config
        model.liveUpdateCurrent(updated)
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
            get: { (config.colors[safe: index] ?? RGBAColor(r: 0, g: 0, b: 0)).swiftUIColor },
            set: { newValue in
                var cs = config.colors
                while cs.count < 3 { cs.append(RGBAColor(r: 0, g: 0, b: 0)) }
                cs[index] = RGBAColor(newValue)
                config.colors = cs
            })
    }

    private func hexString(_ color: RGBAColor) -> String {
        String(format: "#%02X%02X%02X",
               Int((color.r * 255).rounded()),
               Int((color.g * 255).rounded()),
               Int((color.b * 255).rounded()))
    }

    private func save(setAsWallpaper: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "ShaderGradient" : trimmed
        let item: ContentItem
        if let existing {
            var updated = existing
            updated.name = finalName
            updated.shaderGradient = config
            model.updateItem(updated)
            item = updated
        } else {
            item = model.addShaderGradient(config, name: finalName)
        }
        if setAsWallpaper { model.setWallpaper(item) }
        onClose()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
