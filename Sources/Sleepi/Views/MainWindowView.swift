import SwiftUI
import SleepiKit

struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: AppTab? = .wallpapers

    var body: some View {
        NavigationSplitView {
            List(AppTab.allCases, selection: $tab) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 196, ideal: 216, max: 260)
            .safeAreaInset(edge: .top, spacing: 0) { brand }
            .safeAreaInset(edge: .bottom, spacing: 0) { playbackControls }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WindowBackground())
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 880, minHeight: 580)
        .preferredColorScheme(.dark)   // UI is designed dark; keep text contrast correct in Light Mode
    }

    @ViewBuilder
    private var detail: some View {
        switch tab ?? .wallpapers {
        case .wallpapers: WallpapersView()
        case .gradients: GradientsView()
        case .screensaver: ScreensaverSettingsView()
        case .settings: SettingsView()
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Sleepi")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var playbackControls: some View {
        VStack(spacing: 12) {
            Divider().opacity(0.35)

            if model.currentSupportsSpeed {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "speedometer").font(.caption2)
                        Text("Speed").font(.caption.weight(.medium))
                        Spacer()
                        Text(String(format: "%.2f×", model.currentWallpaperSpeed))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(get: { model.currentWallpaperSpeed },
                                       set: { model.setCurrentSpeed($0) }),
                        in: model.currentSpeedRange)
                    .controlSize(.small)
                }
            }

            Button {
                model.togglePause()
            } label: {
                Label(model.isPaused ? "Paused" : "Playing",
                      systemImage: model.isPaused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .tint(model.isPaused ? .orange : .accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 12)
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
