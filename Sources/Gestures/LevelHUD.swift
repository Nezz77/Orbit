import AppKit
import SwiftUI

@MainActor
final class LevelHUD {
    private var panel: NSPanel?
    private var host: NSHostingView<LevelHUDContent>?
    private var hideWork: DispatchWorkItem?

    func show(edge: EdgeAction, level: Double, muted: Bool) {
        let content = LevelHUDContent(edge: edge, level: level, muted: muted)
        if panel == nil {
            let window = NSPanel(
                contentRect: CGRect(x: 0, y: 0, width: 220, height: 62),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = .floating
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let glass = NSGlassEffectView(frame: window.contentRect(forFrameRect: window.frame))
            glass.style = .regular
            glass.cornerRadius = 17
            let host = NSHostingView(rootView: content)
            glass.contentView = host
            window.contentView = glass
            self.host = host
            panel = window
        }

        host?.rootView = content
        let pointer = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main {
            panel?.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - 110, y: screen.visibleFrame.minY + 38))
        }
        panel?.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    func dismiss() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
    }
}

private struct LevelHUDContent: View {
    let edge: EdgeAction
    let level: Double
    let muted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: muted ? "speaker.slash.fill" : edge.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(edge == .brightness ? Color.orbitAmber : Color.orbitBlue)
            ProgressView(value: muted ? 0 : level)
                .tint(edge == .brightness ? .orbitAmber : .orbitBlue)
            Text(muted ? "Muted" : level.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .padding(13)
        .frame(width: 220, height: 62)
        .accessibilityElement(children: .combine)
    }
}
