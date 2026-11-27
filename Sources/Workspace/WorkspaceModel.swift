import AppKit
import Observation
import SwiftUI

enum WorkspacePage: String, CaseIterable, Identifiable {
    case overview, teleprompter, notch, gestures, cleanup, downloads, settings

    var id: Self { self }

    static let primary: [Self] = [.overview, .teleprompter, .notch, .gestures, .cleanup, .downloads]

    var title: String {
        switch self {
        case .overview: "Overview"
        case .teleprompter: "Teleprompter"
        case .notch: "Notch"
        case .gestures: "Trackpad"
        case .cleanup: "Cleanup"
        case .downloads: "Downloads"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .teleprompter: "text.alignleft"
        case .notch: "macbook"
        case .gestures: "hand.draw"
        case .cleanup: "sparkles"
        case .downloads: "arrow.down.to.line"
        case .settings: "gearshape"
        }
    }

    var color: Color {
        switch self {
        case .overview, .teleprompter: .orbitAccent
        case .notch: .orbitCyan
        case .gestures: .orbitAmber
        case .cleanup: .orbitMint
        case .downloads: .orbitBlue
        case .settings: .secondary
        }
    }

    var shortcut: KeyEquivalent {
        KeyEquivalent(Character(String((Self.primary.firstIndex(of: self) ?? 0) + 1)))
    }
}

enum OrbitAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor @Observable
final class WorkspaceModel {
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var started = false
    @ObservationIgnored private var termination: NSObjectProtocol?
    @ObservationIgnored private var openWorkspace: (() -> Void)?

    var selected: WorkspacePage = .overview
    let prompter = PrompterModel()
    let activity = NotchActivity()
    let gestures = GestureController()
    let cleanup = CleanupModel()
    let downloads = DownloadManager()
    private let notchPanel = NotchPanelController()

    var appearance: OrbitAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: "workspace.appearance")
            if started { applyAppearance() }
        }
    }

    var notchEnabled: Bool {
        didSet {
            defaults.set(notchEnabled, forKey: "notch.enabled")
            if started { updateNotch() }
        }
    }

    init() {
        appearance = OrbitAppearance(rawValue: UserDefaults.standard.string(forKey: "workspace.appearance") ?? "") ?? .system
        notchEnabled = UserDefaults.standard.bool(forKey: "notch.enabled")
    }

    func attach(openWorkspace: @escaping () -> Void) {
        self.openWorkspace = openWorkspace
        guard !started else { return }
        started = true

        notchPanel.root = { [weak self] expanded in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(NotchOverlayView(workspace: self, expanded: expanded)
                .preferredColorScheme(self.appearance.colorScheme))
        }
        prompter.onPresentationChange = { [weak self] in self?.updateNotch() }
        gestures.start()
        activity.start()
        downloads.start()
        applyAppearance()
        updateNotch()
        termination = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.prompter.saveDraft()
                self?.prompter.stop()
                self?.gestures.stop()
                self?.activity.stop()
            }
        }
    }

    func navigate(_ page: WorkspacePage) {
        selected = page
        openWorkspace?()
    }

    private func updateNotch() {
        notchPanel.isEnabled = notchEnabled && !prompter.isPresenting
    }

    private func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        notchPanel.refresh()
    }
}
