import SwiftUI
import AppKit
import HazeKit

/// The About page: app identity (icon · name · version · author) and two action
/// buttons — a GitHub link and a (placeholder) donate button.
struct AboutView: View {
    private let githubURL = URL(string: "https://github.com/adrbn/haze")!

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "About")

            VStack(spacing: 18) {
                appIcon

                VStack(spacing: 6) {
                    Text("Haze")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Version \(HazeKit.version)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Live wallpapers, a matching screensaver, and animated Metal gradients — native, lightweight, free.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                        .padding(.top, 2)
                }

                HStack(spacing: 5) {
                    Text("Created by")
                        .foregroundStyle(.secondary)
                    Text("adrbn")
                        .fontWeight(.semibold)
                }
                .font(.callout)

                HStack(spacing: 12) {
                    githubButton
                    donateButton
                }
                .padding(.top, 4)

                Spacer(minLength: 0)

                Text("[GPL-3.0](https://github.com/adrbn/haze/blob/main/LICENSE) · © 2026 Haze contributors")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .tint(.secondary)
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Pieces

    private var appIcon: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: 104, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    private var githubButton: some View {
        Button {
            NSWorkspace.shared.open(githubURL)
        } label: {
            HStack(spacing: 9) {
                Image("github-mark")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 18, height: 18)
                Text("View on GitHub")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Color(red: 0.13, green: 0.15, blue: 0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Open the Haze repository on GitHub")
    }

    private var donateButton: some View {
        Button {
            // Ko-fi link added later.
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Donate")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.55)
        .help("Ko-fi coming soon")
    }
}
