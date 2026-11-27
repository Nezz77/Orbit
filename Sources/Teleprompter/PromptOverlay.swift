import AppKit
import SwiftUI

@MainActor
final class PromptOverlayController: NSObject, NSWindowDelegate {
    var targetScreen: NSScreen?
    private var window: PromptWindow?
    private var screenObservation: NSObjectProtocol?
    private var placement: PromptPlacement = .notch

    func show(placement: PromptPlacement, view: some View, close: @escaping () -> Void) {
        hide()
        self.placement = placement
        let mask: NSWindow.StyleMask = placement == .floating
            ? [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel]
            : [.borderless, .nonactivatingPanel]
        let panel = PromptWindow(contentRect: .zero, styleMask: mask, backing: .buffered, defer: false)
        panel.title = "Orbit Teleprompter"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = placement == .floating
        panel.hasShadow = placement == .floating
        panel.level = placement == .floating ? .floating : .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.minSize = NSSize(width: 460, height: 220)
        panel.closeAction = close
        panel.delegate = self
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host
        window = panel
        position()
        if placement == .fullscreen { panel.makeKeyAndOrderFront(nil) }
        else { panel.orderFrontRegardless() }

        screenObservation = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.position() }
        }
    }

    func hide() {
        if let screenObservation { NotificationCenter.default.removeObserver(screenObservation) }
        screenObservation = nil
        guard let window else { return }
        window.delegate = nil
        window.orderOut(nil)
        window.contentView = nil
        self.window = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window?.closeAction?()
        return false
    }

    private func position() {
        let available = NSScreen.screens
        let screen = targetScreen.flatMap { target in available.first { $0 == target } }
            ?? NSScreen.main ?? available.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let frame: CGRect
        switch placement {
        case .notch:
            let width = min(620, visible.width - 20)
            frame = CGRect(x: screen.frame.midX - width / 2, y: visible.maxY - 260, width: width, height: 256)
        case .floating:
            let width = min(670, visible.width - 20)
            let height = min(365, visible.height - 20)
            frame = CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
        case .fullscreen:
            frame = screen.frame
        }
        window?.setFrame(frame.integral, display: true)
    }
}

private final class PromptWindow: NSPanel {
    var closeAction: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { closeAction?() }
}

struct PromptOverlayView: View {
    let model: PrompterModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 9) {
                OrbitMark(size: 20)
                Text(model.isFinished ? "Finished" : model.isPlaying ? model.mode.rawValue : "Paused")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(model.progress.formatted(.percent.precision(.fractionLength(0))))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.leading, model.placement == .floating ? 62 : 0)

            readingArea

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.orbitAmber)
                    .lineLimit(2)
            }

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        model.seek(to: model.currentWord - 8)
                    } label: {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Back eight words")

                    Button {
                        model.togglePlaying()
                    } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                    .keyboardShortcut(.space, modifiers: [])

                    Button {
                        model.seek(to: model.currentWord + 8)
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Forward eight words")

                    Spacer()
                    Button("Stop", systemImage: "stop.fill") { model.stop() }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(model.placement == .fullscreen ? Color.black : .clear)
        .glassEffect(.regular, in: .rect(cornerRadius: model.placement == .fullscreen ? 0 : 22))
        .padding(model.placement == .fullscreen ? 0 : 5)
        .preferredColorScheme(.dark)
    }

    private var readingArea: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.lines) { line in
                            lineText(line)
                                .id(line.id)
                        }
                    }
                    .padding(.vertical, max(0, proxy.size.height * 0.5 - model.fontSize))
                    .padding(.horizontal, 14)
                    .frame(maxWidth: model.placement == .fullscreen ? 1180 : .infinity)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.top)
                .mask {
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.17),
                                .init(color: .black, location: 0.83), .init(color: .clear, location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .scaleEffect(x: model.mirrored ? -1 : 1)
                .onChange(of: currentLineID) { _, next in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.32)) {
                        scroll.scrollTo(next, anchor: .center)
                    }
                }
            }
        }
    }

    private var currentLineID: Int {
        var lower = 0
        var upper = model.lines.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if model.lines[middle].end <= model.currentWord { lower = middle + 1 }
            else { upper = middle }
        }
        return model.lines.indices.contains(lower) ? model.lines[lower].id : 0
    }

    private func lineText(_ line: PromptLine) -> some View {
        let active = line.id <= model.currentWord && model.currentWord < line.end
        var styled = AttributedString()
        for (offset, word) in line.words.enumerated() {
            let index = line.id + offset
            var piece = AttributedString(offset == 0 ? word : " " + word)
            piece.foregroundColor = index == model.currentWord
                ? Color(red: 0.62, green: 0.99, blue: 0.87)
                : .white.opacity(active ? 0.88 : 0.52)
            styled += piece
        }
        return Text(styled)
            .font(.system(size: model.placement == .fullscreen ? model.fontSize * 1.65 : model.fontSize, weight: .medium))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}
