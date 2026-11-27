import AppKit
import SwiftUI

struct DownloadsView: View {
    @Bindable var manager: DownloadManager
    @State private var linkText = ""
    @State private var filter: DownloadFilter = .all

    private let columns = [GridItem(.flexible(minimum: 130), alignment: .leading),
                           GridItem(.flexible(minimum: 130), alignment: .leading)]

    var body: some View {
        WorkspaceScroll {
            WorkspaceHeader(title: "Downloads", subtitle: "Queue direct file links and manage transfers from one place.") {
                Button("Choose Folder…", systemImage: "folder") {
                    chooseDownloadFolder(startingAt: manager.folder) { manager.folder = $0 }
                }
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }

            OrbitCard {
                VStack(alignment: .leading, spacing: 11) {
                    OrbitSectionTitle(title: "Add links")
                    HStack(alignment: .center, spacing: 10) {
                        TextField("Paste one or more HTTP or HTTPS links", text: $linkText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                            .onSubmit { addLinks() }
                            .accessibilityLabel("Download links")
                        Button("Add to Queue", systemImage: "plus") { addLinks() }
                            .buttonStyle(.glassProminent)
                            .disabled(linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    HStack(spacing: 8) {
                        Label(manager.folder.path(percentEncoded: false), systemImage: "folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(manager.folder.path(percentEncoded: false))
                        Spacer()
                        Picker("Concurrent transfers", selection: $manager.maxConcurrent) {
                            ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .fixedSize()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let message = manager.entryError {
                        Text(message).font(.caption).foregroundStyle(Color.orbitAmber)
                    }
                    if let message = manager.persistenceError {
                        Text(message).font(.caption).foregroundStyle(Color.orbitAmber)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    OrbitSectionTitle(title: "Transfers")
                    Spacer()
                    Picker("Filter transfers", selection: $filter) {
                        ForEach(DownloadFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 252)
                }

                let filtered = manager.items.filter { filter.includes($0.phase) }
                if filtered.isEmpty {
                    OrbitCard {
                        OrbitEmptyState(
                            symbol: "arrow.down.to.line", title: manager.items.isEmpty ? "No downloads yet" : "No matching transfers",
                            message: manager.items.isEmpty ? "Paste a direct file link above to start a download." : "Choose All to see the full queue.",
                            tint: .orbitBlue
                        )
                    }
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { item in
                            DownloadRow(item: item, manager: manager)
                        }
                    }
                }
            }
        }
    }

    private func addLinks() {
        let lines = linkText.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return }
        var failed: [String] = []
        var lastError: String?
        for line in lines {
            if !manager.add(line) {
                failed.append(line)
                lastError = manager.entryError
            }
        }
        linkText = failed.joined(separator: "\n")
        manager.entryError = failed.count <= 1 ? lastError : "\(failed.count) links couldn’t be added. \(lastError ?? "")"
        if failed.count != lines.count { filter = .all }
    }

}

@MainActor
private func chooseDownloadFolder(startingAt folder: URL, onSelection: @escaping (URL) -> Void) {
    let panel = NSOpenPanel()
    panel.title = "Choose Download Folder"
    panel.prompt = "Choose"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = folder
    panel.begin { response in
        if response == .OK, let location = panel.url { onSelection(location) }
    }
}

private enum DownloadFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case completed = "Completed"

    var id: Self { self }

    func includes(_ phase: DownloadPhase) -> Bool {
        switch self {
        case .all: true
        case .active: phase.isActive || phase == .queued
        case .completed: phase == .completed
        }
    }
}

private struct DownloadRow: View {
    let item: DownloadItem
    let manager: DownloadManager

    var body: some View {
        OrbitCard(padding: 12) {
            HStack(alignment: .center, spacing: 12) {
                OrbitIcon(name: symbol, color: tint, size: 36)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(item.error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orbitAmber))
                        .lineLimit(2)
                    if item.phase == .downloading {
                        if let fraction = item.fraction {
                            ProgressView(value: fraction)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                rowActions
            }
        }
    }

    private var detail: String {
        if let error = item.error { return error }
        let size = ByteCountFormatter.string(fromByteCount: item.received, countStyle: .file)
        switch item.phase {
        case .downloading:
            let speed = manager.rates[item.id].map { " · " + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) + "/s" } ?? ""
            if let total = item.total {
                return size + " of " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file) + speed
            }
            return size + speed
        case .completed: return "Completed · \(size)"
        case .paused:
            if item.received == 0 { return "Paused" }
            return item.hasResumeData ? "Paused · \(size)" : "Paused · server requires restarting"
        default:
            return item.phase.rawValue + " · " + (item.source.host() ?? "")
        }
    }

    private var symbol: String {
        switch item.phase {
        case .completed: "checkmark"
        case .failed: "exclamationmark"
        case .paused: "pause"
        default: "arrow.down"
        }
    }

    private var tint: Color {
        switch item.phase {
        case .completed: .orbitMint
        case .failed: .orbitAmber
        default: .orbitBlue
        }
    }

    @ViewBuilder private var rowActions: some View {
        if item.phase == .queued || item.phase == .downloading {
            action("Pause", symbol: "pause.fill") { manager.pause(item.id) }
        }
        if item.phase == .paused || item.phase == .failed {
            action(item.phase == .failed ? "Retry" : "Resume", symbol: "play.fill") { manager.resume(item.id) }
            action(item.phase == .failed ? "Choose Folder and Retry…" : "Choose Folder and Resume…", symbol: "folder") {
                chooseDownloadFolder(startingAt: manager.folder) { folder in
                    manager.resume(item.id, in: folder)
                }
            }
        }
        if let url = item.savedFile, item.phase == .completed {
            action("Reveal in Finder", symbol: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        if !item.phase.isActive {
            action("Remove from queue", symbol: "xmark") { manager.remove(item.id) }
        }
    }

    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Image(systemName: symbol) }
            .buttonStyle(.glass)
            .accessibilityLabel(title)
            .help(title)
    }
}
