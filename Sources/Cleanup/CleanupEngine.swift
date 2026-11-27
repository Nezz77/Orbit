import Darwin
import Foundation

// The category roots follow Mac Cleaner's user-cache and developer scans.
enum CleanupCategory: String, CaseIterable, Identifiable, Sendable {
    case caches = "App caches"
    case logs = "User logs"
    case xcode = "Xcode DerivedData"
    case homebrew = "Homebrew cache"
    case npm = "npm cache"

    var id: Self { self }

    var relativePath: String {
        switch self {
        case .caches: "Library/Caches"
        case .logs: "Library/Logs"
        case .xcode: "Library/Developer/Xcode/DerivedData"
        case .homebrew: "Library/Caches/Homebrew"
        case .npm: ".npm/_cacache"
        }
    }

    var icon: String {
        switch self {
        case .caches: "shippingbox"
        case .logs: "list.bullet.rectangle"
        case .xcode: "hammer"
        case .homebrew: "mug"
        case .npm: "cube.transparent"
        }
    }
}

struct CleanupItem: Identifiable, Sendable {
    let url: URL
    let category: CleanupCategory
    let bytes: Int64
    fileprivate let identity: CleanupIdentity

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

fileprivate struct CleanupIdentity: Equatable, Sendable {
    let device: dev_t
    let inode: ino_t
    let mode: mode_t
}

struct CleanupScan: Sendable {
    var items: [CleanupItem] = []
    var unreadableRoots: [CleanupCategory] = []
    var incompleteItems = 0
}

struct CleanupResult: Sendable {
    var moved: Set<URL> = []
    var failures: [String] = []
}

struct CleanupEngine: Sendable {
    let home: URL

    func scan() -> CleanupScan {
        let manager = FileManager.default
        let home = home.resolvingSymlinksInPath()
        var result = CleanupScan()

        for category in CleanupCategory.allCases {
            let expected = home.appending(path: category.relativePath)
            let root = expected.resolvingSymlinksInPath()
            guard root.path == expected.standardizedFileURL.path, root.path.hasPrefix(home.path + "/") else {
                result.unreadableRoots.append(category)
                continue
            }

            let children: [URL]
            do {
                children = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                continue
            } catch {
                result.unreadableRoots.append(category)
                continue
            }

            guard let rootIdentity = identity(at: root) else {
                result.unreadableRoots.append(category)
                continue
            }

            for child in children {
                // Homebrew gets its own row group so no two choices can include the same files.
                if category == .caches && child.lastPathComponent == "Homebrew" { continue }
                guard let itemIdentity = identity(at: child), itemIdentity.device == rootIdentity.device,
                      itemIdentity.mode == S_IFDIR || itemIdentity.mode == S_IFREG else { continue }
                let (bytes, complete) = measure(child, itemIdentity: itemIdentity)
                guard complete else {
                    result.incompleteItems += 1
                    continue
                }
                if bytes > 0 {
                    result.items.append(CleanupItem(url: child, category: category, bytes: bytes, identity: itemIdentity))
                }
            }
        }
        result.items.sort {
            if $0.bytes == $1.bytes { return $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
            return $0.bytes > $1.bytes
        }
        return result
    }

    func trash(_ items: [CleanupItem]) -> CleanupResult {
        let home = home.resolvingSymlinksInPath()
        var result = CleanupResult()
        for item in items {
            let expected = home.appending(path: item.category.relativePath).standardizedFileURL
            let parent = item.url.deletingLastPathComponent().standardizedFileURL
            guard parent.path == expected.path,
                  parent.resolvingSymlinksInPath().path == expected.path,
                  expected.path.hasPrefix(home.path + "/"),
                  let parentIdentity = identity(at: parent),
                  parentIdentity.device == item.identity.device,
                  identity(at: item.url) == item.identity else {
                result.failures.append("\(item.name) changed since the scan.")
                continue
            }
            do {
                var destination: NSURL?
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &destination)
                result.moved.insert(item.id)
            } catch {
                result.failures.append("\(item.name) couldn’t be moved to Trash.")
            }
        }
        return result
    }

    private func identity(at url: URL) -> CleanupIdentity? {
        var metadata = stat()
        let status = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return lstat(path, &metadata)
        }
        guard status == 0 else { return nil }
        return CleanupIdentity(device: metadata.st_dev, inode: metadata.st_ino, mode: metadata.st_mode & S_IFMT)
    }

    private func measure(_ url: URL, itemIdentity: CleanupIdentity) -> (Int64, Bool) {
        let keys: Set<URLResourceKey> = [.fileAllocatedSizeKey, .isSymbolicLinkKey, .isDirectoryKey, .volumeIdentifierKey]
        guard let root = try? url.resourceValues(forKeys: keys) else { return (0, false) }
        var size = Int64(root.fileAllocatedSize ?? 0)
        if itemIdentity.mode == S_IFREG { return (size, true) }

        var complete = true
        guard let walk = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [],
            errorHandler: { _, _ in complete = false; return true }
        ) else { return (0, false) }

        for case let entry as URL in walk {
            guard let values = try? entry.resourceValues(forKeys: keys) else {
                complete = false
                walk.skipDescendants()
                continue
            }
            if values.isSymbolicLink == true {
                walk.skipDescendants()
                continue
            }
            if let childVolume = values.volumeIdentifier as? NSObject,
               let rootVolume = root.volumeIdentifier as? NSObject,
               childVolume != rootVolume {
                complete = false
                walk.skipDescendants()
                continue
            }
            size += Int64(values.fileAllocatedSize ?? 0)
        }
        return (size, complete)
    }
}
