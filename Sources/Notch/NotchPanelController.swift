import AppKit
import SwiftUI

@MainActor
final class NotchPanelController {
    var root: ((Bool) -> AnyView)?
    var isEnabled = false {
        didSet {
            guard oldValue != isEnabled else { return }
            if isEnabled { show() }
            else { hide() }
        }
    }

    private var panel: NotchPanel?
    private var hosting: HoverHostingView?
    private var screensObserver: NSObjectProtocol?
    private var pendingCollapse: DispatchWorkItem?
    private var expanded = false

    func refresh() {
        guard isEnabled, let hosting, let root else { return }
        hosting.rootView = root(expanded)
        position()
    }

    private func show() {
        guard let root else { return }
        if panel == nil {
            let window = NotchPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.hasShadow = false
            window.isMovable = false
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none

            let host = HoverHostingView(rootView: root(false))
            host.sizingOptions = []
            host.onEnter = { [weak self] in self?.mouseEntered() }
            host.onExit = { [weak self] in self?.mouseExited() }
            window.contentView = host
            panel = window
            hosting = host
        }
        screensObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.position() }
        }
        refresh()
        panel?.orderFrontRegardless()
    }

    private func hide() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
        if let screensObserver { NotificationCenter.default.removeObserver(screensObserver) }
        screensObserver = nil
        expanded = false
        panel?.orderOut(nil)
    }

    private func mouseEntered() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
        guard isEnabled, !expanded else { return }
        expanded = true
        refresh()
    }

    private func mouseExited() {
        pendingCollapse?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isEnabled, let panel = self.panel,
                  !panel.frame.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation) else { return }
            self.expanded = false
            self.refresh()
        }
        pendingCollapse = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func position() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let size = expanded ? CGSize(width: 350, height: 218) : CGSize(width: 237, height: 38)
        let top = min(screen.frame.maxY - screen.safeAreaInsets.top, screen.visibleFrame.maxY)
        let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: top - size.height)
        panel?.setFrame(CGRect(origin: origin, size: size).integral, display: true)
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class HoverHostingView: NSHostingView<AnyView> {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var hoverTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .inVisibleRect, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
