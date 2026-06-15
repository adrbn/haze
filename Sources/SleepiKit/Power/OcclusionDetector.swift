import AppKit

/// Detects whether the desktop is fully covered by other windows, using an
/// active `CGWindowList` scan (no Screen Recording permission needed — only
/// window geometry is read, never contents). Re-evaluates on app-activation,
/// Space changes, and display reconfiguration — no polling timer.
@MainActor
public final class OcclusionDetector {
    public var onChange: ((Bool) -> Void)?
    public private(set) var currentlyOccluded = false

    private var tokens: [NSObjectProtocol] = []
    private var pendingReeval: DispatchWorkItem?
    private var pollTimer: Timer?

    public init() {}

    public func start() {
        let ws = NSWorkspace.shared.notificationCenter
        tokens.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                     object: nil, queue: .main) { [weak self] _ in self?.scheduleEvaluate() })
        tokens.append(ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                     object: nil, queue: .main) { [weak self] _ in self?.scheduleEvaluate() })
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                     object: nil, queue: .main) { [weak self] _ in self?.scheduleEvaluate() })
        // Window visibility changes (Mission Control / swipe-to-desktop) — the
        // signal that the wallpaper became visible again.
        tokens.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                     object: nil, queue: .main) { [weak self] _ in self?.scheduleEvaluate() })
        evaluate()
    }

    /// Evaluate now, then again shortly after — Space/Mission-Control transitions
    /// settle asynchronously, so the immediate read can still see stale coverage.
    private func scheduleEvaluate() {
        evaluate()
        pendingReeval?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        pendingReeval = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    public func stop() {
        pendingReeval?.cancel()
        pendingReeval = nil
        pollTimer?.invalidate()
        pollTimer = nil
        for token in tokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        tokens.removeAll()
    }

    deinit {
        pendingReeval?.cancel()
        pollTimer?.invalidate()
        for token in tokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
    }

    public func evaluate() {
        let occluded = Self.computeOccluded()
        if occluded != currentlyOccluded {
            currentlyOccluded = occluded
            Log.power.debug("occluded -> \(occluded, privacy: .public)")
            onChange?(occluded)
        }
        updatePollTimer()
    }

    /// "Show Desktop" / Mission Control don't fire reliable notifications for
    /// desktop-level windows, so while covered we poll occlusion — that way the
    /// wallpaper resumes on reveal without the user re-selecting it. Runs only
    /// while occluded (the wallpaper is paused then, so cost is negligible).
    private func updatePollTimer() {
        if currentlyOccluded {
            guard pollTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.evaluate() }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    static func computeOccluded() -> Bool {
        let screens = NSScreen.screens.map(\.frame)
        guard !screens.isEmpty else { return false }
        return ScreenCoverage.allScreensCovered(screens: screens, windows: coveringWindowFrames())
    }

    /// Opaque, normal-level windows belonging to other apps, converted from
    /// CoreGraphics (top-left origin) to AppKit (bottom-left) global coordinates.
    static func coveringWindowFrames() -> [CGRect] {
        // Height of the primary display (origin at 0,0) anchors the Y flip.
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.map(\.frame.maxY).max()
        guard let primaryHeight else { return [] }

        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }

        var rects: [CGRect] = []
        for window in list {
            let layer = (window[kCGWindowLayer as String] as? Int) ?? 0
            if layer != 0 { continue }                                   // only normal app windows
            let alpha = (window[kCGWindowAlpha as String] as? Double) ?? 1
            if alpha < 0.95 { continue }                                 // skip translucent overlays
            if (window[kCGWindowOwnerPID as String] as? Int) == myPID { continue }
            guard let boundsAny = window[kCGWindowBounds as String],
                  let cg = CGRect(dictionaryRepresentation: boundsAny as! CFDictionary) else { continue }
            rects.append(CGRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height))
        }
        return rects
    }
}
