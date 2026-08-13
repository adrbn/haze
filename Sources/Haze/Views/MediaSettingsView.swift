import SwiftUI
import HazeKit

/// Adjustments for a file-backed item — video, GIF or still.
///
/// Gradients have had their own editor since the start; everything else could
/// only be renamed, favourited or deleted, so "Edit…" was missing from the
/// context menu for most of a library. These are the knobs `ItemSettings`
/// already carried with no way to reach them.
///
/// Changes apply as you make them: if the item is the live wallpaper you watch
/// the desktop follow, which is the only honest way to pick a scaling mode.
struct MediaSettingsView: View {
    @EnvironmentObject private var model: AppModel

    let item: ContentItem
    let onClose: () -> Void

    @State private var scaling: Scaling
    @State private var speed: Double
    @State private var fps: Int

    init(item: ContentItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        _scaling = State(initialValue: item.settings.scaling)
        _speed = State(initialValue: item.settings.speed)
        _fps = State(initialValue: item.settings.fps)
    }

    /// Stills have no playback rate to set.
    private var supportsSpeed: Bool {
        item.type == .video || item.type == .animatedImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 22) {
                scalingControl
                if supportsSpeed { speedControl }
                fpsControl
            }
            .padding(24)

            Spacer(minLength: 0)

            HStack {
                Button("Reset") { reset() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Done") { onClose() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(24)
        }
        .frame(width: 460, height: supportsSpeed ? 520 : 440)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ContentThumbnailView(item: item)
                .frame(width: 96, height: 60)
                .glassCard(cornerRadius: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(item.type.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
    }

    private var scalingControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Scaling", detail: scalingHint)
            Picker("", selection: $scaling) {
                ForEach(Scaling.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: scaling) { apply() }
        }
    }

    private var scalingHint: String {
        switch scaling {
        case .fill: return "Covers the screen, cropping the overflow."
        case .fit: return "Shows all of it, letterboxed to fit."
        case .stretch: return "Distorts to fill — ignores the aspect ratio."
        case .center: return "Actual size, centred."
        }
    }

    private var speedControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Speed", detail: String(format: "%.2f×", speed))
            Slider(value: $speed, in: 0.25...2.0) { editing in
                if !editing { apply() }
            }
            .onChange(of: speed) { model.liveUpdateCurrent(edited()) }
        }
    }

    private var fpsControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Frame rate", detail: fps == 0 ? "Follows the display" : "\(fps) fps")
            Picker("", selection: $fps) {
                Text("Display").tag(0)
                Text("60").tag(60)
                Text("30").tag(30)
                Text("24").tag(24)
                Text("15").tag(15)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: fps) { apply() }
            Text("A lower cap costs less battery. Below 24 fps motion starts to judder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func label(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The item as the controls currently describe it.
    private func edited() -> ContentItem {
        var copy = item
        copy.settings.scaling = scaling
        copy.settings.speed = speed
        copy.settings.fps = fps
        return copy
    }

    private func apply() {
        model.updateItem(edited())
    }

    private func reset() {
        let defaults = ItemSettings()
        scaling = defaults.scaling
        speed = defaults.speed
        fps = defaults.fps
        apply()
    }
}
