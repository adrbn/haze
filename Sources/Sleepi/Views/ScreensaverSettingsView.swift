import SwiftUI
import SleepiKit

struct ScreensaverSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var installed = ScreensaverInstaller.isInstalled
    @State private var statusMessage: String?
    @State private var category: LibraryCategory = .all

    private var shown: [ContentItem] {
        model.items(in: category, pinnedFirst: model.settings.screensaverItemID)
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Screensaver",
                       subtitle: "Shown when your Mac is idle")

            installCard
                .padding(.horizontal, 24)
                .padding(.bottom, 4)

            CategoryBar(selection: $category)

            ScrollView {
                pickerSection
                    .padding(24)
            }
        }
    }

    // MARK: Install card

    @ViewBuilder
    private var installCard: some View {
        if installed {
            installedCard
        } else {
            notInstalledCard
        }
    }

    /// Compact, single-row card once the saver is installed.
    private var installedCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Color.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Screensaver installed")
                    .font(.headline)
                Text(statusMessage ?? "macOS controls when it starts — set the idle timer in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button { ScreensaverPreviewController.shared.start() } label: {
                Label("Preview", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            Button("Open Settings") { ScreensaverInstaller.openSystemSettings() }
            Menu {
                Button("Reinstall / Update") { install() }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .fixedSize()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass()
    }

    /// Fuller call-to-action before the saver is installed.
    private var notInstalledCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill").foregroundStyle(Color.orange)
                Text("Screensaver not installed yet").font(.headline)
            }
            Text("macOS controls when the screensaver starts. Install it here, then choose “SleepiSaver” and set the idle timer in System Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button { install() } label: {
                    Label("Install Screensaver", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button { ScreensaverPreviewController.shared.start() } label: {
                    Label("Preview Full Screen", systemImage: "play.fill")
                }
                .controlSize(.large)
            }
            if let statusMessage {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass()
    }

    // MARK: Picker

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screensaver content").font(.headline)
            Text("Pick what the screensaver shows. Defaults to your current wallpaper if none is selected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if shown.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: libraryGridColumns, spacing: 18) {
                    ForEach(shown) { item in
                        ContentCard(item: item,
                                    isSelected: model.settings.screensaverItemID == item.id,
                                    tag: item.type.shortTag,
                                    isFavorite: model.isFavorite(item),
                                    onToggleFavorite: { model.toggleFavorite(item) }) {
                            model.setScreensaver(item)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: category == .favorites ? "star" : "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(category == .all
                 ? "Add some wallpapers or gradients first."
                 : "Nothing in this category yet.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
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
