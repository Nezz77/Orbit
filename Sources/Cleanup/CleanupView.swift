import AppKit
import SwiftUI

struct CleanupView: View {
    @Bindable var model: CleanupModel
    @State private var confirming = false

    var body: some View {
        WorkspaceScroll {
            WorkspaceHeader(title: "Cleanup", subtitle: "Review caches, logs, and build files before moving them to Trash.") {
                Button(model.hasScanned ? "Scan Again" : "Scan Storage", systemImage: "magnifyingglass") { model.scan() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(model.scanning || model.cleaning)
            }

            if let message = model.scanNotice {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(Color.orbitAmber)
            }
            if let message = model.resultNotice {
                Label(message, systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(Color.orbitMint)
            }
            if !model.failures.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.failures.enumerated()), id: \.offset) { _, message in
                        Label(message, systemImage: "exclamationmark.circle")
                    }
                }
                .font(.callout)
                .foregroundStyle(Color.orbitAmber)
            }

            if model.scanning {
                OrbitCard {
                    ProgressView("Scanning storage…")
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 178)
                }
            } else if !model.hasScanned {
                OrbitCard {
                    OrbitEmptyState(
                        symbol: "internaldrive", title: "Ready to scan",
                        message: "Orbit checks app caches, user logs, Xcode DerivedData, Homebrew, and npm.",
                        tint: .orbitMint
                    )
                }
            } else if model.items.isEmpty {
                OrbitCard {
                    OrbitEmptyState(symbol: "checkmark.seal", title: "No cleanup items found",
                                    message: "Scan again after your apps rebuild their caches.", tint: .orbitMint)
                }
            } else {
                summary
                results
            }
        }
        .alert("Move \(model.selection.count.formatted()) \(model.selection.count == 1 ? "item" : "items") to Trash?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) { model.moveSelectionToTrash() }
        } message: {
            Text("The selected items use about \(formattedSize(model.selectedBytes)). macOS keeps them in Trash until it’s emptied.")
        }
    }

    private var summary: some View {
        HStack(spacing: 17) {
            OrbitIcon(name: "internaldrive", color: .orbitMint)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(formattedSize(model.scanBytes)) found")
                    .font(.system(size: 17, weight: .semibold))
                Text("\(model.selection.count.formatted()) selected · \(formattedSize(model.selectedBytes))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if model.cleaning { ProgressView().controlSize(.small) }
            Button("Move to Trash…", systemImage: "trash") { confirming = true }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(model.selection.isEmpty || model.cleaning)
        }
        .padding(13)
        .glassEffect(.regular, in: .rect(cornerRadius: 17))
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Category", selection: $model.category) {
                    Text("All categories").tag(nil as CleanupCategory?)
                    ForEach(CleanupCategory.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                .labelsHidden()
                .accessibilityLabel("Filter cleanup by category")
                .frame(maxWidth: 220)

                Spacer()
                if !model.visibleItems.isEmpty {
                    Button("Select Visible") { model.selection.formUnion(model.visibleItems.map(\.id)) }
                        .buttonStyle(.glass)
                }
                if !model.selection.isEmpty {
                    Button("Clear Selection") { model.selection.removeAll() }
                        .buttonStyle(.glass)
                }
            }
            .disabled(model.cleaning)

            if model.visibleItems.isEmpty {
                OrbitCard {
                    Text("No items in this category.")
                        .foregroundStyle(.secondary)
                }
            }

            LazyVStack(spacing: 7) {
                ForEach(model.visibleItems) { item in
                    OrbitCard(padding: 11) {
                        HStack(spacing: 11) {
                            Toggle(isOn: Binding(get: { model.selection.contains(item.id) }, set: { _ in model.toggle(item) })) {
                                HStack(spacing: 10) {
                                    OrbitIcon(name: item.category.icon, color: .orbitMint, size: 28)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                        Text(item.category.rawValue).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                            .disabled(model.cleaning)
                            Spacer()
                            Text(formattedSize(item.bytes))
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel("Reveal \(item.name) in Finder")
                            .help(item.url.path)
                        }
                    }
                }
            }
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
