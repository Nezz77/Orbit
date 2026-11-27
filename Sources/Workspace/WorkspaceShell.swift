import AppKit
import SwiftUI

struct WorkspaceShell: View {
    let workspace: WorkspaceModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
            Rectangle()
                .fill(.primary.opacity(scheme == .dark ? 0.10 : 0.08))
                .frame(width: 1)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background { OrbitBackdrop() }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onAppear {
            workspace.attach {
                openWindow(id: "workspace")
                NSApp.activate()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                OrbitMark(size: 34)
                Text("Orbit")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.6)
            }
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 10)
            .padding(.top, 16)
            .padding(.bottom, 21)

            ForEach(WorkspacePage.primary) { page in
                SidebarItem(page: page, selected: workspace.selected == page) {
                    workspace.selected = page
                }
            }

            Spacer(minLength: 20)

            Button {
                workspace.notchEnabled.toggle()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(workspace.notchEnabled ? Color.orbitMint : .secondary.opacity(0.52))
                        .frame(width: 7, height: 7)
                    Text(workspace.notchEnabled ? "Notch on" : "Notch off")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 11)
                .frame(height: 34)
                .contentShape(.capsule)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(workspace.notchEnabled ? "Hide notch panel" : "Show notch panel")
            .padding(.horizontal, 5)
            .padding(.bottom, 9)

            SidebarItem(page: .settings, selected: workspace.selected == .settings) {
                workspace.selected = .settings
            }
        }
        .padding(.horizontal, 13)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity)
        .background(scheme == .dark ? Color.black.opacity(0.17) : Color.white.opacity(0.39))
    }

    @ViewBuilder
    private var detail: some View {
        switch workspace.selected {
        case .overview: OverviewView(workspace: workspace)
        case .teleprompter: PrompterView(prompter: workspace.prompter)
        case .notch: NotchSettingsView(workspace: workspace)
        case .gestures: GesturesView(controller: workspace.gestures)
        case .cleanup: CleanupView(model: workspace.cleanup)
        case .downloads: DownloadsView(manager: workspace.downloads)
        case .settings: OrbitSettingsView(workspace: workspace)
        }
    }
}

private struct SidebarItem: View {
    let page: WorkspacePage
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: page.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? Color.orbitAccent : page.color)
                    .frame(width: 20)
                Text(page.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(height: 39)
            .background {
                if selected || hovering {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selected ? Color.orbitAccent.opacity(0.13) : .primary.opacity(0.045))
                }
            }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.orbitAccent.opacity(0.19), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct OrbitSettingsView: View {
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        @Bindable var gestures = workspace.gestures

        WorkspaceScroll {
            WorkspaceHeader(title: "Settings")
            OrbitCard {
                VStack(alignment: .leading, spacing: 13) {
                    OrbitSectionTitle(title: "Appearance")
                    Picker("Interface appearance", selection: $workspace.appearance) {
                        ForEach(OrbitAppearance.allCases) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 350)
                }
            }
            OrbitCard {
                VStack(alignment: .leading, spacing: 12) {
                    OrbitSectionTitle(title: "Panels and gestures")
                    Toggle("Show the notch panel", isOn: $workspace.notchEnabled)
                    Toggle("Enable trackpad edge gestures", isOn: $gestures.enabled)
                }
                .toggleStyle(.switch)
            }
            OrbitCard {
                VStack(alignment: .leading, spacing: 12) {
                    OrbitSectionTitle(title: "About Orbit")
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                        .foregroundStyle(.secondary)
                    if let licenses = Bundle.main.resourceURL?.appending(path: "Licenses") {
                        Button("Open source acknowledgments") { NSWorkspace.shared.open(licenses) }
                            .buttonStyle(.glass)
                    }
                }
            }
        }
    }
}
