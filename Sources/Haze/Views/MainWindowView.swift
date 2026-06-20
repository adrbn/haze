import SwiftUI
import HazeKit

struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: AppTab = .wallpapers
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            switch model.settings.navLayout {
            case .sidebar: sidebarLayout
            case .bar: barLayout
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .preferredColorScheme(.dark)   // UI is designed dark; keep text contrast correct in Light Mode
    }

    // MARK: Sidebar layout

    private var sidebarLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(AppTab.allCases, selection: Binding(get: { tab }, set: { tab = $0 ?? tab })) { item in
                Label(item.title, systemImage: item.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.vertical, 7)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 280)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 26)   // clear the traffic-light area
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { playbackControls }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WindowBackground())
                .overlay(alignment: .topLeading) { collapseButton }
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// Toggles the sidebar in/out. Shown only when the sidebar is collapsed
    /// (when expanded, the List's own header area already holds the toggle and a
    /// second button there would be redundant) — here it lets the user bring it
    /// back from the detail pane.
    @ViewBuilder
    private var collapseButton: some View {
        if columnVisibility == .detailOnly {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { columnVisibility = .all }
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(9)
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: Circle())
            .padding(.top, 30)
            .padding(.leading, 14)
            .help("Show sidebar")
        }
    }

    // MARK: Floating-bar layout

    private var barLayout: some View {
        let edge = model.settings.barEdge
        return ZStack(alignment: edge == .top ? .top : .bottom) {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WindowBackground())
                .safeAreaInset(edge: edge == .top ? .top : .bottom, spacing: 0) {
                    Color.clear.frame(height: 74)   // reserve room for the floating bar
                }

            MainNavBar(tab: $tab)
                .padding(.horizontal, 18)
                .padding(.top, edge == .top ? 30 : 0)
                .padding(.bottom, edge == .bottom ? 16 : 0)
        }
    }

    // MARK: Shared

    @ViewBuilder
    private var detail: some View {
        switch tab {
        case .wallpapers: WallpapersView()
        case .screensaver: ScreensaverSettingsView()
        case .settings: SettingsView()
        case .about: AboutView()
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 12) {
            Divider().opacity(0.35)
            if model.currentSupportsSpeed { speedControl }
            playPauseButton
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var speedControl: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "speedometer").font(.caption2)
                Text("Speed").font(.caption.weight(.medium))
                Spacer()
                Text(String(format: "%.2f×", model.currentWallpaperSpeed))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: speedBinding, in: model.currentSpeedRange, step: 0.1)
                .controlSize(.small)
        }
    }

    private var playPauseButton: some View {
        Button { model.togglePause() } label: {
            Label(model.isPaused ? "Paused" : "Playing",
                  systemImage: model.isPaused ? "play.fill" : "pause.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
        }
        .buttonStyle(.bordered)
        .tint(model.isPaused ? .orange : .accentColor)
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: {
                let r = model.currentSpeedRange
                return min(max(model.currentWallpaperSpeed, r.lowerBound), r.upperBound)
            },
            set: { model.setCurrentSpeed($0) })
    }
}

/// The floating liquid-glass navigation bar: section pills on the left, compact
/// playback controls on the right.
private struct MainNavBar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var tab: AppTab

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(AppTab.allCases) { item in
                    Button { tab = item } label: {
                        Label(item.title, systemImage: item.systemImage)
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(tab == item ? Color.accentColor : Color.clear, in: Capsule())
                            .foregroundStyle(tab == item ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 8)

            if model.currentSupportsSpeed {
                HStack(spacing: 6) {
                    Image(systemName: "speedometer").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: speedBinding, in: model.currentSpeedRange, step: 0.1)
                        .controlSize(.small)
                        .frame(width: 120)
                    Text(String(format: "%.2f×", model.currentWallpaperSpeed))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }

            Button { model.togglePause() } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.isPaused ? Color.orange : Color.accentColor)
            .help(model.isPaused ? "Resume" : "Pause")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .liquidGlass(cornerRadius: 22)
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: {
                let r = model.currentSpeedRange
                return min(max(model.currentWallpaperSpeed, r.lowerBound), r.upperBound)
            },
            set: { model.setCurrentSpeed($0) })
    }
}

/// A quiet, on-brand backdrop so the glass panels have something to float over.
struct WindowBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(white: 0.08), Color(white: 0.04)],
            startPoint: .top, endPoint: .bottom)
        .overlay(
            RadialGradient(
                colors: [Color.accentColor.opacity(0.18), .clear],
                center: .topTrailing, startRadius: 40, endRadius: 520)
        )
        .ignoresSafeArea()
    }
}
