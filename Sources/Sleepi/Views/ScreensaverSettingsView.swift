import SwiftUI
import SleepiKit

struct ScreensaverSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var installed = ScreensaverInstaller.isInstalled
    @State private var statusMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Screensaver",
                       subtitle: "Shown when your Mac is idle")

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    infoCard
                    pickerSection
                }
                .padding(24)
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: installed ? "checkmark.seal.fill" : "moon.zzz.fill")
                    .foregroundStyle(installed ? Color.green : Color.orange)
                Text(installed ? "Sleepi screensaver is installed" : "Screensaver not installed yet")
                    .font(.headline)
            }
            Text("macOS controls when the screensaver starts. Install it here, then choose “SleepiSaver” and set the idle timer in System Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    ScreensaverPreviewController.shared.start()
                } label: {
                    Label("Preview Full Screen", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(installed ? "Reinstall / Update" : "Install Screensaver") { install() }
                Button("Open Screen Saver Settings") { ScreensaverInstaller.openSystemSettings() }
            }
            Text("Preview runs the screensaver full-screen right now — move the mouse or press a key to exit.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let statusMessage {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass()
    }

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screensaver content").font(.headline)
            Text("Pick what the screensaver shows. Defaults to your current wallpaper if none is selected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if model.items.isEmpty {
                Text("Add some wallpapers or gradients first.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: libraryGridColumns, spacing: 18) {
                    ForEach(model.items) { item in
                        ContentCard(item: item,
                                    isSelected: model.settings.screensaverItemID == item.id) {
                            model.setScreensaver(item)
                        }
                    }
                }
            }
        }
    }

    private func install() {
        let ok = ScreensaverInstaller.install()
        installed = ScreensaverInstaller.isInstalled
        statusMessage = ok
            ? "Installed. Select “SleepiSaver” in Screen Saver settings."
            : "Install failed — check Console.app for details."
        if ok { ScreensaverInstaller.openSystemSettings() }
    }
}
