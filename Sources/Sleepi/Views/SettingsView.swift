import SwiftUI
import SleepiKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Settings",
                       subtitle: "Tune resource use and startup behaviour")

            Form {
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
                    Toggle("Launch Sleepi at login", isOn: boolBinding(\.launchAtLogin))
                }

                Section("About") {
                    LabeledContent("Version", value: SleepiKit.version)
                    LabeledContent("License", value: "GPL-3.0")
                    Text("Sleepi is free and open source — live wallpapers, screensaver, and Metal gradients, built to sip resources.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
}
