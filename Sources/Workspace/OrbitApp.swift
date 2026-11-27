import AppKit
import SwiftUI

@main
struct OrbitApp: App {
    @State private var workspace = WorkspaceModel()

    var body: some Scene {
        Window("Orbit", id: "workspace") {
            WorkspaceShell(workspace: workspace)
                .preferredColorScheme(workspace.appearance.colorScheme)
                .tint(.orbitAccent)
                .frame(minWidth: 860, minHeight: 590)
        }
        .defaultSize(width: 1120, height: 748)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandMenu("Workspace") {
                ForEach(WorkspacePage.primary) { page in
                    Button(page.title) { workspace.navigate(page) }
                        .keyboardShortcut(page.shortcut, modifiers: .command)
                }
                Divider()
                Button("Settings…") { workspace.navigate(.settings) }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

        MenuBarExtra("Orbit", systemImage: "circle.dotted.circle") {
            OrbitMenu(workspace: workspace)
        }
    }
}

private struct OrbitMenu: View {
    let workspace: WorkspaceModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Orbit") {
            openWindow(id: "workspace")
            NSApp.activate()
        }
        Button(workspace.notchEnabled ? "Hide Notch Panel" : "Show Notch Panel") {
            workspace.notchEnabled.toggle()
        }
        if workspace.prompter.isPresenting {
            Button(workspace.prompter.isPlaying ? "Pause Teleprompter" : "Resume Teleprompter") {
                workspace.prompter.togglePlaying()
            }
            Button("Stop Teleprompter") { workspace.prompter.stop() }
        }
        if workspace.downloads.activeCount > 0 {
            Button("Downloads (\(workspace.downloads.activeCount) active)") {
                openWindow(id: "workspace")
                workspace.navigate(.downloads)
            }
        }
        Divider()
        Button("Quit Orbit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
