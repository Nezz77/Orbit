import SwiftUI

struct GesturesView: View {
    @Bindable var controller: GestureController

    var body: some View {
        WorkspaceScroll {
            WorkspaceHeader(
                title: "Trackpad",
                subtitle: "Adjust brightness and volume by sliding along the edges of your trackpad."
            ) {
                Toggle("Edge gestures", isOn: $controller.enabled)
                    .toggleStyle(.switch)
            }

            if controller.enabled && !controller.isRunning {
                HStack {
                    Label("Orbit couldn’t connect to a supported trackpad.", systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color.orbitAmber)
                    Button("Try Again") { controller.startTrackpadIfEnabled() }
                        .buttonStyle(.glass)
                }
            }

            OrbitCard {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        OrbitSectionTitle(title: "Edge controls")
                        Spacer()
                        Button("Swap Sides", systemImage: "arrow.left.arrow.right") { controller.swapped.toggle() }
                            .buttonStyle(.glass)
                    }
                    TrackpadIllustration(left: controller.left, right: controller.right, bottomOnly: controller.bottomOnly,
                                         mediaEnabled: controller.mediaStrip, enabled: controller.isRunning)
                        .frame(height: 160)
                    HStack(spacing: 24) {
                        levelControl(controller.left)
                        levelControl(controller.right)
                    }
                }
            }

            OrbitCard {
                VStack(alignment: .leading, spacing: 13) {
                    OrbitSectionTitle(title: "Gesture settings")
                    HStack(alignment: .top, spacing: 25) {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Hold to activate", selection: $controller.modifier) {
                                ForEach(ModifierRequirement.allCases) { Text($0.label).tag($0) }
                            }
                            Toggle("Bottom quarter only", isOn: $controller.bottomOnly)
                            Toggle("Freeze pointer while sliding", isOn: $controller.freezePointer)
                            Toggle("Quarter-step movement", isOn: $controller.precise)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Haptic feedback", isOn: $controller.haptics)
                            Toggle("Show Liquid Glass HUD", isOn: $controller.showHUD)
                            Toggle("Double-tap top-right to mute", isOn: $controller.quickMute)
                            Toggle("Bottom edge media controls", isOn: $controller.mediaStrip)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if controller.mediaStrip && !controller.hasAccessibility {
                        Button("Allow Accessibility for Media Keys…") { controller.requestAccessibility() }
                            .buttonStyle(.glass)
                    }
                }
            }
        }
        .onAppear {
            controller.updatePermissions()
            controller.refreshLevels()
        }
    }

    private func levelControl(_ edge: EdgeAction) -> some View {
        let value = controller.level(for: edge)
        let canAdjust = controller.canAdjust(edge)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(edge.label, systemImage: edge.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(canAdjust ? value.formatted(.percent.precision(.fractionLength(0))) : "Unavailable")
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { controller.level(for: edge) },
                set: { controller.setLevel($0, for: edge) }
            ), in: 0...1)
            .tint(edge == .brightness ? .orbitAmber : .orbitBlue)
            .disabled(!canAdjust)
            .accessibilityLabel(edge.label)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TrackpadIllustration: View {
    let left: EdgeAction
    let right: EdgeAction
    let bottomOnly: Bool
    let mediaEnabled: Bool
    let enabled: Bool

    var body: some View {
        HStack(spacing: 22) {
            edgeLabel("Left edge", action: left)
                .frame(maxWidth: .infinity, alignment: .trailing)
            GeometryReader { proxy in
                let height = proxy.size.height
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.primary.opacity(0.05))
                        .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
                    HStack {
                        edgeBand(left, height: bottomOnly ? height * 0.24 : height - 14)
                        Spacer()
                        edgeBand(right, height: bottomOnly ? height * 0.24 : height - 14)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(7)
                    if mediaEnabled {
                        Image(systemName: "playpause.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.orbitAccent)
                            .frame(width: 75, height: 20)
                            .background(Color.orbitAccent.opacity(0.15), in: .capsule)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 8)
                    }
                    Image(systemName: "hand.draw")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: 235)
            edgeLabel("Right edge", action: right)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityHidden(true)
    }

    private func edgeLabel(_ side: String, action: EdgeAction) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(side).font(.caption).foregroundStyle(.secondary)
            Text(action.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(action == .brightness ? Color.orbitAmber : Color.orbitBlue)
        }
    }

    private func edgeBand(_ edge: EdgeAction, height: CGFloat) -> some View {
        let color = edge == .brightness ? Color.orbitAmber : .orbitBlue
        return Image(systemName: "arrow.up.arrow.down")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 33, height: height)
            .background(color.opacity(enabled ? 0.22 : 0.11), in: RoundedRectangle(cornerRadius: 13))
    }
}
