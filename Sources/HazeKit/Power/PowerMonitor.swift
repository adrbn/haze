import AppKit
import IOKit.ps

/// Watches system power/sleep/lock state and the desktop window occlusion, feeds
/// a `PlaybackPolicy`, and notifies an observer whenever the render decision
/// flips. Lives on the main run loop.
@MainActor
public final class PowerMonitor {
    public private(set) var policy: PlaybackPolicy
    /// Called (on main) whenever `shouldRender` changes.
    public var onShouldRenderChange: ((Bool) -> Void)?

    private var lastShouldRender: Bool
    private var powerSource: CFRunLoopSource?
    private var powerStateToken: NSObjectProtocol?

    public init(settings: AppSettings) {
        var initial = PlaybackPolicy()
        initial.applyPreferences(settings)
        policy = initial
        lastShouldRender = initial.shouldRender
        subscribe()
        refreshPowerState()
        emit()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        if let powerStateToken {
            NotificationCenter.default.removeObserver(powerStateToken)
        }
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
        }
    }

    // MARK: Mutators

    public func updateSettings(_ settings: AppSettings) {
        policy.applyPreferences(settings)
        refreshPowerState()
        emit()
    }

    public func setUserPaused(_ paused: Bool) {
        guard policy.userPaused != paused else { return }
        policy.userPaused = paused
        emit()
    }

    public func setOccluded(_ occluded: Bool) {
        guard policy.occluded != occluded else { return }
        policy.occluded = occluded
        emit()
    }

    public var isUserPaused: Bool { policy.userPaused }

    // MARK: Subscriptions

    private func subscribe() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(screensDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(screensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenLocked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenUnlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        // Pause the desktop wallpaper while the screensaver runs, so it doesn't
        // compete with the screensaver for the GPU (causing video stutter).
        dnc.addObserver(self, selector: #selector(screensaverStarted), name: NSNotification.Name("com.apple.screensaver.didstart"), object: nil)
        dnc.addObserver(self, selector: #selector(screensaverStopped), name: NSNotification.Name("com.apple.screensaver.didstop"), object: nil)

        // NSProcessInfoPowerStateDidChange may be delivered off the main thread,
        // so request main-queue delivery (the handler mutates AppKit/Metal views).
        powerStateToken = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.refreshPowerState()
            self?.emit()
        }

        subscribePowerSource()
    }

    /// IOKit power-source change callback (covers AC <-> battery transitions).
    private func subscribePowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.refreshPowerState()
            monitor.emit()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
    }

    // MARK: Handlers

    @objc private func systemWillSleep() { policy.systemAsleep = true; emit() }
    @objc private func systemDidWake() { policy.systemAsleep = false; refreshPowerState(); emit() }
    @objc private func screensDidSleep() { policy.displayAsleep = true; emit() }
    @objc private func screensDidWake() { policy.displayAsleep = false; emit() }
    @objc private func screenLocked() { policy.screenLocked = true; emit() }
    @objc private func screenUnlocked() { policy.screenLocked = false; emit() }
    @objc private func screensaverStarted() { policy.screensaverActive = true; emit() }
    @objc private func screensaverStopped() { policy.screensaverActive = false; emit() }

    private func refreshPowerState() {
        policy.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        policy.onBattery = Self.isOnBattery()
    }

    private func emit() {
        let value = policy.shouldRender
        guard value != lastShouldRender else { return }
        lastShouldRender = value
        Log.power.debug("shouldRender -> \(value, privacy: .public)")
        onShouldRenderChange?(value)
    }

    /// `true` when the Mac is running on battery (no AC adapter providing power).
    static func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String? else {
            return false
        }
        return type == kIOPMBatteryPowerKey
    }
}
