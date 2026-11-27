import SwiftUI

struct NotchOverlayView: View {
    let workspace: WorkspaceModel
    let expanded: Bool

    var body: some View {
        Group {
            if expanded { controls }
            else { compact }
        }
        .padding(4)
    }

    private var compact: some View {
        HStack(spacing: 9) {
            Image(systemName: "circle.dotted.circle")
                .foregroundStyle(Color.orbitAccent)
            Text(workspace.activity.timerRunning ? workspace.activity.timerText : "Orbit")
                .fontWeight(.semibold)
                .monospacedDigit()
            Spacer(minLength: 0)
            if workspace.downloads.activeCount > 0 {
                Label(workspace.downloads.activeCount.formatted(), systemImage: "arrow.down")
                    .foregroundStyle(Color.orbitBlue)
            }
            Image(systemName: workspace.activity.batterySymbol)
                .foregroundStyle(Color.orbitMint)
            if workspace.activity.batteryLevel != nil {
                Text(workspace.activity.batteryText).monospacedDigit()
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 13)
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                OrbitMark(size: 23)
                Text("Orbit")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    workspace.navigate(.notch)
                } label: {
                    Image(systemName: "arrow.up.right")
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Open Orbit")
            }

            HStack(spacing: 12) {
                Label(workspace.activity.batteryText, systemImage: workspace.activity.batterySymbol)
                    .foregroundStyle(Color.orbitMint)
                Spacer(minLength: 0)
                Label(workspace.activity.cpuText, systemImage: "cpu")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if workspace.downloads.activeCount > 0 {
                    Button {
                        workspace.navigate(.downloads)
                    } label: {
                        Label(workspace.downloads.activeCount.formatted(), systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.orbitBlue)
                    .accessibilityLabel("Open active downloads")
                } else {
                    Text(workspace.activity.storageText).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()

            if let activeDownload = workspace.downloads.currentTransfer {
                if let progress = activeDownload.fraction {
                    ProgressView(value: progress)
                        .accessibilityLabel(activeDownload.name)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(activeDownload.name)
                }
            }

            Divider()

            HStack(spacing: 7) {
                MediaButtons(controller: workspace.gestures)
                Spacer(minLength: 0)
                TimerControls(activity: workspace.activity)
            }

            if !workspace.gestures.hasAccessibility {
                Button("Allow media controls") { workspace.gestures.requestAccessibility() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .onAppear { workspace.gestures.updatePermissions() }
    }
}

struct NotchSettingsView: View {
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        @Bindable var activity = workspace.activity

        WorkspaceScroll {
            WorkspaceHeader(title: "Notch", subtitle: "Keep your system status and quick controls beside the camera.") {
                Toggle("Show notch", isOn: $workspace.notchEnabled)
                    .toggleStyle(.switch)
            }

            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 14) {
                    stat("Battery", workspace.activity.batteryText, workspace.activity.batterySymbol, .orbitMint)
                    stat("CPU", workspace.activity.cpuText, "cpu", .orbitAccent)
                    stat("Free storage", workspace.activity.storageText, "internaldrive", .orbitCyan)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                OrbitCard {
                    VStack(alignment: .leading, spacing: 13) {
                        OrbitSectionTitle(title: "Timer")
                        TimerControls(activity: workspace.activity)
                    }
                }

                OrbitCard {
                    VStack(alignment: .leading, spacing: 13) {
                        OrbitSectionTitle(title: "Media controls")
                        MediaButtons(controller: workspace.gestures)
                        if !workspace.gestures.hasAccessibility {
                            Button("Allow Accessibility…") { workspace.gestures.requestAccessibility() }
                                .buttonStyle(.link)
                        }
                    }
                }
            }

            OrbitCard {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        OrbitSectionTitle(title: "Clipboard history")
                        Spacer()
                        Toggle("Remember copied text", isOn: $activity.capturesClipboard)
                            .toggleStyle(.switch)
                    }
                    if workspace.activity.capturesClipboard && !workspace.activity.clips.isEmpty {
                        ForEach(workspace.activity.clips) { clip in
                            HStack(spacing: 12) {
                                Text(clip.text.replacingOccurrences(of: "\n", with: " "))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                Button {
                                    workspace.activity.copy(clip)
                                } label: {
                                    Label("Copy", systemImage: "document.on.document")
                                }
                                .buttonStyle(.glass)
                            }
                        }
                        Button("Clear History") { workspace.activity.clearClipboardHistory() }
                            .buttonStyle(.glass)
                    } else {
                        Text(workspace.activity.capturesClipboard
                             ? "New text you copy will appear here."
                             : "Keep up to 15 copied text items in memory while Orbit is open.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { workspace.gestures.updatePermissions() }
    }

    private func stat(_ name: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            OrbitIcon(name: icon, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 16, weight: .semibold)).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 17))
        .accessibilityElement(children: .combine)
    }
}

private struct TimerControls: View {
    let activity: NotchActivity

    var body: some View {
        if activity.timerRunning {
            HStack(spacing: 8) {
                Text(activity.timerText)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                Button {
                    activity.stopTimer()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Stop timer")
            }
        } else {
            Menu {
                ForEach([1, 5, 10, 15, 25], id: \.self) { minutes in
                    Button(minutes == 1 ? "1 minute" : "\(minutes) minutes") {
                        activity.startTimer(minutes: minutes)
                    }
                }
            } label: {
                Label("Start Timer", systemImage: "timer")
            }
            .fixedSize()
        }
    }
}

private struct MediaButtons: View {
    let controller: GestureController

    var body: some View {
        HStack(spacing: 5) {
            mediaButton("Previous track", "backward.fill", .previous)
            mediaButton("Play or pause", "playpause.fill", .playPause)
            mediaButton("Next track", "forward.fill", .next)
        }
        .disabled(!controller.hasAccessibility)
    }

    private func mediaButton(_ label: String, _ icon: String, _ command: MediaKeyController.Command) -> some View {
        Button {
            controller.sendMedia(command)
        } label: {
            Image(systemName: icon)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(label)
        .help(label)
    }
}
