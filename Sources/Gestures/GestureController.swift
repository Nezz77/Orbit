import AppKit
import Observation

@MainActor @Observable
final class GestureController: @preconcurrency SlideEngineDelegate {
    private(set) var isRunning = false
    private(set) var hasAccessibility = false
    private(set) var volume = 0.0
    private(set) var brightness = 0.0
    private(set) var supportsVolume = true
    private(set) var supportsBrightness = true
    private(set) var muted = false

    var enabled = UserDefaults.standard.bool(forKey: "trackpad.enabled") {
        didSet {
            defaults.set(enabled, forKey: "trackpad.enabled")
            if started { startTrackpadIfEnabled() }
        }
    }
    var swapped = UserDefaults.standard.bool(forKey: "trackpad.swapSides") {
        didSet { defaults.set(swapped, forKey: "trackpad.swapSides") }
    }
    var haptics = UserDefaults.standard.object(forKey: "trackpad.haptics") as? Bool ?? true {
        didSet { defaults.set(haptics, forKey: "trackpad.haptics") }
    }
    var precise = UserDefaults.standard.bool(forKey: "trackpad.precise") {
        didSet { defaults.set(precise, forKey: "trackpad.precise") }
    }
    var quickMute = UserDefaults.standard.object(forKey: "trackpad.quickMute") as? Bool ?? true {
        didSet { defaults.set(quickMute, forKey: "trackpad.quickMute") }
    }
    var mediaStrip = UserDefaults.standard.bool(forKey: "trackpad.mediaStrip") {
        didSet { defaults.set(mediaStrip, forKey: "trackpad.mediaStrip") }
    }
    var bottomOnly = UserDefaults.standard.bool(forKey: "trackpad.bottomOnly") {
        didSet { defaults.set(bottomOnly, forKey: "trackpad.bottomOnly") }
    }
    var showHUD = UserDefaults.standard.object(forKey: "trackpad.showHUD") as? Bool ?? true {
        didSet {
            defaults.set(showHUD, forKey: "trackpad.showHUD")
            if !showHUD { hud.dismiss() }
        }
    }
    var freezePointer = UserDefaults.standard.bool(forKey: "trackpad.freezePointer") {
        didSet {
            defaults.set(freezePointer, forKey: "trackpad.freezePointer")
            if !freezePointer { freezer.end() }
        }
    }
    var modifier = ModifierRequirement(rawValue: UserDefaults.standard.string(forKey: "trackpad.modifier") ?? "") ?? .option {
        didSet { defaults.set(modifier.rawValue, forKey: "trackpad.modifier") }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let monitor = TrackpadMonitor()
    @ObservationIgnored private let engine = SlideEngine()
    @ObservationIgnored private let sound = AudioController.shared
    @ObservationIgnored private let backlight = BrightnessController.shared
    @ObservationIgnored private let hud = LevelHUD()
    @ObservationIgnored private let freezer = CursorFreezer()
    @ObservationIgnored private var windowObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var pendingRelease: DispatchWorkItem?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastActive = false

    var left: EdgeAction { swapped ? .volume : .brightness }
    var right: EdgeAction { swapped ? .brightness : .volume }

    func start() {
        guard !started else { return }
        started = true
        engine.delegate = self
        engine.configuration = { [weak self] in self?.configuration() ?? EngineConfiguration() }
        sound.onChange = { [weak self] in self?.refreshLevels() }
        sound.startObserving()
        updatePermissions()
        refreshLevels()
        startTrackpadIfEnabled()

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePermissions()
                self?.refreshLevels()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                guard let self, self.started else { return }
                self.refreshLevels()
                self.startTrackpadIfEnabled()
            }
        }
    }

    func stop() {
        guard started else { return }
        started = false
        stopTrackpad()
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        windowObserver = nil
        wakeObserver = nil
        sound.onChange = nil
        sound.stopObserving()
    }

    func updatePermissions() {
        hasAccessibility = AccessibilityPermission.isTrusted
    }

    func requestAccessibility() {
        if !AccessibilityPermission.requestIfNeeded() { AccessibilityPermission.openSystemSettings() }
        updatePermissions()
    }

    func sendMedia(_ command: MediaKeyController.Command) {
        updatePermissions()
        guard hasAccessibility else { return }
        MediaKeyController.shared.send(command)
    }

    func level(for edge: EdgeAction) -> Double {
        edge == .volume ? volume : brightness
    }

    func canAdjust(_ edge: EdgeAction) -> Bool {
        switch edge {
        case .volume: supportsVolume
        case .brightness: supportsBrightness
        }
    }

    func setLevel(_ value: Double, for edge: EdgeAction, displayHUD: Bool = false) {
        guard canAdjust(edge) else { return }
        switch edge {
        case .volume:
            sound.setLevel(value)
            volume = sound.level
            muted = sound.isMuted
        case .brightness:
            backlight.setLevel(value)
            brightness = backlight.level
        }
        if showHUD, displayHUD {
            hud.show(edge: edge, level: level(for: edge), muted: edge == .volume && muted)
        }
    }

    func refreshLevels() {
        sound.refresh()
        backlight.refresh()
        volume = sound.level
        brightness = backlight.level
        muted = sound.isMuted
        supportsVolume = sound.supportsVolumeControl
        supportsBrightness = backlight.supportsPreciseControl || hasAccessibility
    }

    func startTrackpadIfEnabled() {
        stopTrackpad()
        guard enabled else { return }
        let run = generation
        monitor.onFrame = { [weak self] frame in
            DispatchQueue.main.async {
                guard let self, self.isRunning, self.generation == run else { return }
                self.consume(frame)
            }
        }
        isRunning = monitor.start()
    }

    private func stopTrackpad() {
        generation = UUID()
        pendingRelease?.cancel()
        pendingRelease = nil
        monitor.stop()
        isRunning = false
        lastActive = false
        engine.reset()
        freezer.end()
        hud.dismiss()
    }

    private func consume(_ frame: TouchFrame) {
        let touchCount = frame.activeContacts.count
        if touchCount == 1 && !lastActive { refreshLevels() }
        lastActive = touchCount > 0
        engine.process(frame)

        if engine.isTrackingSlide && freezePointer {
            freezer.begin()
            freezer.hold()
        } else {
            freezer.end()
        }

        pendingRelease?.cancel()
        guard engine.isTrackingSlide || lastActive else {
            pendingRelease = nil
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.engine.process(TouchFrame(timestamp: frame.timestamp + 0.18, contacts: []))
            self.lastActive = false
            self.freezer.end()
        }
        pendingRelease = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func configuration() -> EngineConfiguration {
        var config = EngineConfiguration()
        config.leftEdge = left
        config.rightEdge = right
        config.bottomQuarterOnly = bottomOnly
        config.currentVolume = volume
        config.currentBrightness = brightness
        config.mediaStripEnabled = mediaStrip && hasAccessibility
        config.tapToPlayEnabled = config.mediaStripEnabled
        config.quickMuteEnabled = quickMute && supportsVolume
        config.requireModifier = modifier
        config.preciseSliding = precise
        return config
    }

    func slideEngine(_ engine: SlideEngine, didBeginSlide target: EdgeAction) {}

    func slideEngine(_ engine: SlideEngine, didUpdateSlide target: EdgeAction, level: Double) {
        setLevel(level, for: target, displayHUD: true)
    }

    func slideEngine(_ engine: SlideEngine, didEndSlide target: EdgeAction, level: Double) {}

    func slideEngine(_ engine: SlideEngine, didTick target: EdgeAction, level: Double) {
        if haptics, canAdjust(target) { Haptics.shared.tick(.medium) }
    }

    func slideEngine(_ engine: SlideEngine, didRecognize command: MediaCommand) {
        switch command {
        case .mute:
            sound.toggleMute()
            muted = sound.isMuted
            if showHUD { hud.show(edge: .volume, level: volume, muted: muted) }
            if haptics { Haptics.shared.tick(.strong) }
        case .previous: sendMedia(.previous)
        case .playPause: sendMedia(.playPause)
        case .next: sendMedia(.next)
        }
    }
}
