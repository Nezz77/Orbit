import Foundation
import Observation

@MainActor @Observable
final class CleanupModel {
    private(set) var items: [CleanupItem] = []
    var selection: Set<URL> = []
    var category: CleanupCategory?
    private(set) var scanning = false
    private(set) var cleaning = false
    private(set) var hasScanned = false
    private(set) var scanNotice: String?
    private(set) var resultNotice: String?
    private(set) var failures: [String] = []
    @ObservationIgnored private let engine = CleanupEngine(home: FileManager.default.homeDirectoryForCurrentUser)

    var visibleItems: [CleanupItem] {
        guard let category else { return items }
        return items.filter { $0.category == category }
    }
    var scanBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var selectedBytes: Int64 { items.reduce(0) { $0 + (selection.contains($1.id) ? $1.bytes : 0) } }

    func scan() {
        guard !scanning, !cleaning else { return }
        scanning = true
        resultNotice = nil
        scanNotice = nil
        failures = []
        selection.removeAll()

        Task {
            let engine = engine
            let report = await Task.detached(priority: .utility) { engine.scan() }.value
            items = report.items
            hasScanned = true
            scanning = false
            var messages: [String] = []
            if !report.unreadableRoots.isEmpty {
                messages.append("Could not scan \(report.unreadableRoots.map(\.rawValue).joined(separator: ", ")).")
            }
            if report.incompleteItems > 0 {
                messages.append("\(report.incompleteItems.formatted()) partially readable items were skipped.")
            }
            scanNotice = messages.isEmpty ? nil : messages.joined(separator: " ")
        }
    }

    func toggle(_ item: CleanupItem) {
        if selection.contains(item.id) { selection.remove(item.id) }
        else { selection.insert(item.id) }
    }

    func moveSelectionToTrash() {
        guard !scanning, !cleaning, !selection.isEmpty else { return }
        let chosen = items.filter { selection.contains($0.id) }
        cleaning = true

        Task {
            let engine = engine
            let result = await Task.detached(priority: .utility) { engine.trash(chosen) }.value
            items.removeAll { result.moved.contains($0.id) }
            selection.subtract(result.moved)
            cleaning = false
            failures = result.failures
            resultNotice = result.moved.isEmpty ? nil : "\(result.moved.count.formatted()) \(result.moved.count == 1 ? "item" : "items") moved to Trash."
        }
    }
}
