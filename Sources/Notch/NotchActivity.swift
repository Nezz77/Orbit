import AppKit
import IOKit.ps
import Observation

struct ClipboardClip: Identifiable {
    let id = UUID()
    let text: String
}

@MainActor @Observable
final class NotchActivity {
    private(set) var batteryLevel: Int?
    private(set) var onPower = false
    private(set) var availableStorage: Int64?
    private(set) var cpuUsage: Double?
    private(set) var remainingSeconds = 0
    private(set) var clips: [ClipboardClip] = []
    var capturesClipboard = false {
        didSet {
            pasteboardChange = NSPasteboard.general.changeCount
            if !capturesClipboard { clips.removeAll() }
        }
    }

    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var timerEnd: Date?
    @ObservationIgnored private var pasteboardChange = 0
    @ObservationIgnored private var lastSystemRead = Date.distantPast
    @ObservationIgnored private var cpuTicks: host_cpu_load_info?

    var batteryText: String { batteryLevel.map { "\($0)%" } ?? "No battery" }
    var batterySymbol: String {
        if onPower, batteryLevel != nil { return "battery.100percent.bolt" }
        switch batteryLevel ?? 100 {
        case 0..<12: return "battery.0percent"
        case 12..<38: return "battery.25percent"
        case 38..<63: return "battery.50percent"
        case 63..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
    var storageText: String { availableStorage.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Unavailable" }
    var cpuText: String { cpuUsage.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—" }
    var timerText: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }
    var timerRunning: Bool { remainingSeconds > 0 }

    func start() {
        guard ticker == nil else { return }
        sampleSystem()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
    }

    func startTimer(minutes: Int) {
        guard minutes > 0 else { return }
        remainingSeconds = minutes * 60
        timerEnd = Date().addingTimeInterval(Double(remainingSeconds))
    }

    func stopTimer() {
        timerEnd = nil
        remainingSeconds = 0
    }

    func copy(_ clip: ClipboardClip) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(clip.text, forType: .string)
        pasteboardChange = board.changeCount
    }

    func clearClipboardHistory() {
        clips.removeAll()
    }

    private func tick() {
        let now = Date()
        if let timerEnd {
            remainingSeconds = max(0, Int(ceil(timerEnd.timeIntervalSince(now))))
            if remainingSeconds == 0 {
                self.timerEnd = nil
                NSSound.beep()
            }
        }
        if now.timeIntervalSince(lastSystemRead) >= 5 { sampleSystem() }
        if capturesClipboard { sampleClipboard() }
    }

    private func sampleSystem() {
        lastSystemRead = Date()
        let values = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(
            forKeys: [.volumeAvailableCapacityKey]
        )
        availableStorage = values?.volumeAvailableCapacity.map(Int64.init)
        sampleBattery()
        sampleCPU()
    }

    private func sampleBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in list {
            guard let values = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = values[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = values[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            batteryLevel = min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded())))
            onPower = (values[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return
        }
        batteryLevel = nil
        onPower = false
    }

    private func sampleCPU() {
        var next = host_cpu_load_info()
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &next) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return }
        defer { cpuTicks = next }
        guard let previous = cpuTicks else { return }
        let a = next.cpu_ticks, b = previous.cpu_ticks
        let user = Double(a.0 &- b.0)
        let system = Double(a.1 &- b.1)
        let idle = Double(a.2 &- b.2)
        let nice = Double(a.3 &- b.3)
        let total = user + system + idle + nice
        if total > 0 { cpuUsage = (user + system + nice) / total }
    }

    private func sampleClipboard() {
        let board = NSPasteboard.general
        guard pasteboardChange != board.changeCount else { return }
        pasteboardChange = board.changeCount

        let ignoredTypes: Set<String> = [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType"
        ]
        guard (board.types ?? []).allSatisfy({ !ignoredTypes.contains($0.rawValue) }),
              let text = board.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 100_000 else { return }

        clips.removeAll { $0.text == text }
        clips.insert(ClipboardClip(text: text), at: 0)
        if clips.count > 15 { clips.removeLast(clips.count - 15) }
    }
}
