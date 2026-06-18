import AppKit
import SwiftUI
import HazeKit

/// Runs the app as a menu-bar agent. Creates the main window lazily so the app
/// stays invisible (accessory) until the user opens it.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static private(set) weak var shared: AppDelegate?

    private let model = AppModel.shared
    private var mainWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.bootstrap()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func showMainWindow() {
        if mainWindow == nil {
            let root = MainWindowView().environmentObject(model)
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = ""
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)   // UI is designed dark
            // Managed window in its own Space — don't float as a tile over another
            // app's full-screen Space; activating switches to the desktop Space.
            window.collectionBehavior = [.fullScreenPrimary]
            window.minSize = NSSize(width: 900, height: 620)
            // Default sized so the Wallpapers grid shows exactly 3×3 presets with
            // none cut: width fits 3 columns (sidebar + 3 tiles), height ends right
            // after the third row (no 4th-row peek).
            window.setContentSize(NSSize(width: 1120, height: 700))
            window.center()
            window.delegate = self
            mainWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)

        // Re-bind the wallpaper to all Spaces when the app is opened (cheap, no
        // rebuild) — covers any Space created while the window was closed.
        DispatchQueue.main.async { [weak self] in
            self?.model.reaffirmWallpaper()
        }
    }

    // MARK: Gradient editor — its own window (the Metal preview renders reliably
    // in a window, unlike a SwiftUI sheet).

    enum GradientEditorTarget {
        case newFluid, newClassic, existing(ContentItem)
    }

    private var editorWindow: NSWindow?

    func showGradientEditor(_ target: GradientEditorTarget) {
        let close: () -> Void = { [weak self] in
            self?.editorWindow?.close()
            self?.editorWindow = nil
        }

        let root: AnyView
        switch target {
        case .newFluid:
            root = AnyView(ShaderGradientEditorView(config: ShaderGradientPresets.default.config,
                                                    name: "My Fluid Gradient", existing: nil, onClose: close)
                .environmentObject(model))
        case .newClassic:
            root = AnyView(GradientEditorView(config: GradientPresets.default.config,
                                              name: "My Gradient", existing: nil, onClose: close)
                .environmentObject(model))
        case .existing(let item):
            if item.type == .shaderGradient {
                root = AnyView(ShaderGradientEditorView(config: item.shaderGradient ?? ShaderGradientPresets.default.config,
                                                        name: item.name, existing: item, onClose: close)
                    .environmentObject(model))
            } else {
                root = AnyView(GradientEditorView(config: item.gradient ?? GradientPresets.default.config,
                                                  name: item.name, existing: item, onClose: close)
                    .environmentObject(model))
            }
        }

        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = ""
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = true
        window.center()
        editorWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to background agent once the UI is dismissed.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
