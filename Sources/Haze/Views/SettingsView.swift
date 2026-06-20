import SwiftUI
import HazeKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Settings",
                       subtitle: "Tune resource use and startup behaviour")

            Form {
                Section("Window") {
                    Picker("Navigation", selection: navLayoutBinding) {
                        Text("Sidebar").tag(NavLayout.sidebar)
                        Text("Floating bar").tag(NavLayout.bar)
                    }
                    if model.settings.navLayout == .bar {
                        Picker("Bar position", selection: barEdgeBinding) {
                            Text("Top").tag(BarEdge.top)
                            Text("Bottom").tag(BarEdge.bottom)
                        }
                    }
                    Toggle("Match macOS wallpaper", isOn: boolBinding(\.matchSystemWallpaper))
                    Text("Sets a matching still as your macOS desktop picture so Mission Control, lock and login screens match the live wallpaper.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Performance") {
                    Toggle("Pause when fully covered", isOn: boolBinding(\.pauseWhenOccluded))
                    Toggle("Pause when the display sleeps", isOn: boolBinding(\.pauseOnDisplaySleep))
                    Toggle("Pause on battery", isOn: boolBinding(\.pauseOnBattery))
                    Toggle("Pause in Low Power Mode", isOn: boolBinding(\.pauseInLowPowerMode))
                    Picker("Frame-rate cap", selection: fpsBinding) {
                        Text("Auto (match display)").tag(0)
                        Text("24 fps").tag(24)
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                }

                Section("Video") {
                    Toggle("Play video sound", isOn: boolBinding(\.videoSoundEnabled))
                }

                Section("Startup") {
                    Toggle("Launch Haze at login", isOn: boolBinding(\.launchAtLogin))
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: {
                var updated = model.settings
                updated[keyPath: keyPath] = $0
                model.updateSettings(updated)
            })
    }

    private var fpsBinding: Binding<Int> {
        Binding(
            get: { model.settings.globalFPSCap },
            set: {
                var updated = model.settings
                updated.globalFPSCap = $0
                model.updateSettings(updated)
            })
    }

    private var navLayoutBinding: Binding<NavLayout> {
        Binding(
            get: { model.settings.navLayout },
            set: {
                var updated = model.settings
                updated.navLayout = $0
                model.updateSettings(updated)
            })
    }

    private var barEdgeBinding: Binding<BarEdge> {
        Binding(
            get: { model.settings.barEdge },
            set: {
                var updated = model.settings
                updated.barEdge = $0
                model.updateSettings(updated)
            })
    }
}
