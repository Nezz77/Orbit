import Foundation
import Observation

enum DownloadPhase: String, Codable, Sendable {
    case queued = "Queued"
    case downloading = "Downloading"
    case pausing = "Pausing"
    case paused = "Paused"
    case finishing = "Saving"
    case completed = "Completed"
    case failed = "Failed"

    var isActive: Bool { self == .downloading || self == .pausing || self == .finishing }
}

struct DownloadItem: Identifiable, Codable, Sendable {
    let id: UUID
    let source: URL
    let folder: URL
    var name: String
    var phase: DownloadPhase = .queued
    var received: Int64 = 0
    var total: Int64?
    var savedFile: URL?
    var error: String?
    var hasResumeData = false

    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, max(0, Double(received) / Double(total)))
    }
}

@MainActor @Observable
final class DownloadManager {
    private(set) var items: [DownloadItem]
    private(set) var rates: [UUID: Int64] = [:]
    private(set) var persistenceError: String?
    var entryError: String?

    var maxConcurrent: Int {
        didSet {
            defaults.set(maxConcurrent, forKey: "downloads.parallel")
            if started { schedule() }
        }
    }

    var folder: URL {
        didSet { defaults.set(folder.path, forKey: "downloads.folder") }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storage: URL
    @ObservationIgnored private var started = false
    @ObservationIgnored private var active: [Int: Transfer] = [:]
    @ObservationIgnored private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        let delegate = DownloadDelegate(manager: self)
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: .main)
    }()

    private struct Transfer {
        let id: UUID
        let task: URLSessionDownloadTask
        let resumed: Bool
        var lastSample = ProcessInfo.processInfo.systemUptime
        var lastBytes: Int64 = 0
    }

    init(storage: URL = OrbitStorage.appSupport.appending(path: "Downloads"), defaults: UserDefaults = .standard) {
        self.storage = storage
        self.defaults = defaults
        if let path = defaults.string(forKey: "downloads.folder"), !path.isEmpty {
            folder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            folder = URL.downloadsDirectory
        }
        maxConcurrent = min(5, max(1, defaults.object(forKey: "downloads.parallel") as? Int ?? 3))
        let state = storage.appending(path: "Queue.json")
        do {
            items = try JSONDecoder().decode([DownloadItem].self, from: Data(contentsOf: state))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            items = []
        } catch {
            items = []
            persistenceError = "The saved download queue couldn’t be read. \(error.localizedDescription)"
            // Keep the unreadable history available if the queue is written again.
            let snapshot = storage.appending(path: "Queue-unreadable-\(UUID().uuidString).json")
            try? FileManager.default.moveItem(at: state, to: snapshot)
        }

        for index in items.indices {
            if items[index].phase.isActive {
                items[index].phase = .paused
            }
            if items[index].phase == .paused || items[index].phase == .failed {
                items[index].hasResumeData = FileManager.default.fileExists(
                    atPath: storage.appending(path: items[index].id.uuidString + ".resume").path
                )
            }
        }
    }

    var activeCount: Int { items.filter { $0.phase.isActive }.count }
    var currentTransfer: DownloadItem? { items.first { $0.phase == .downloading } }

    func start() {
        guard !started else { return }
        started = true
        schedule()
    }

    @discardableResult
    func add(_ text: String) -> Bool {
        guard let source = DownloadFiles.validatedURL(text) else {
            entryError = DownloadFailure.invalidLink.localizedDescription
            return false
        }
        if items.contains(where: { $0.source == source && ($0.phase.isActive || $0.phase == .queued || $0.phase == .paused) }) {
            entryError = DownloadFailure.duplicate.localizedDescription
            return false
        }
        entryError = nil
        let item = DownloadItem(id: UUID(), source: source, folder: folder, name: DownloadFiles.filename(for: nil, source: source))
        items.insert(item, at: 0)
        persist()
        if started { schedule() }
        return true
    }

    func pause(_ id: UUID) {
        guard let index = index(for: id) else { return }
        if items[index].phase == .queued {
            items[index].phase = .paused
            persist()
            return
        }
        guard items[index].phase == .downloading,
              let transfer = active.values.first(where: { $0.id == id }) else { return }

        items[index].phase = .pausing
        rates.removeValue(forKey: id)
        persist()
        let taskID = transfer.task.taskIdentifier
        transfer.task.cancel { [weak self] data in
            DispatchQueue.main.async {
                self?.finishPausing(taskID: taskID, data: data)
            }
        }
    }

    func resume(_ id: UUID) {
        guard let index = index(for: id), [.paused, .failed].contains(items[index].phase) else { return }
        items[index].phase = .queued
        items[index].error = nil
        persist()
        if started { schedule() }
    }

    func remove(_ id: UUID) {
        guard let index = index(for: id), !items[index].phase.isActive else { return }
        items.remove(at: index)
        clearCheckpoint(id)
        if FileManager.default.fileExists(atPath: stagedFile(id).path) {
            // This file is private transfer staging. Completed downloads live in the chosen folder.
            try? FileManager.default.removeItem(at: stagedFile(id))
        }
        persist()
    }

    private func schedule() {
        var availableSlots = maxConcurrent - activeCount
        guard availableSlots > 0 else { return }

        // Rows show newest first, while transfers start in the order they were queued.
        for index in items.indices.reversed() where items[index].phase == .queued {
            guard availableSlots > 0 else { break }
            launch(index)
            if items[index].phase.isActive {
                availableSlots -= 1
            }
        }
    }

    private func launch(_ index: Int) {
        let item = items[index]
        if let values = try? stagedFile(item.id).resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
            completeStaged(item, bytes: Int64(size), taskID: nil)
            return
        }
        guard (try? item.folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            items[index].phase = .failed
            items[index].error = DownloadFailure.missingFolder.localizedDescription
            persist()
            return
        }

        let resume = try? Data(contentsOf: checkpoint(item.id))
        let task: URLSessionDownloadTask
        if let resume, !resume.isEmpty {
            task = session.downloadTask(withResumeData: resume)
        } else {
            items[index].received = 0
            items[index].total = nil
            task = session.downloadTask(with: item.source)
        }
        items[index].phase = .downloading
        active[task.taskIdentifier] = Transfer(
            id: item.id, task: task, resumed: resume?.isEmpty == false, lastBytes: items[index].received
        )
        persist()
        task.resume()
    }

    fileprivate func didWrite(task: URLSessionDownloadTask, received: Int64, expected: Int64) {
        let taskID = task.taskIdentifier
        guard var transfer = active[taskID], let index = index(for: transfer.id), items[index].phase == .downloading else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - transfer.lastSample
        guard elapsed >= 0.20 || items[index].received == 0 else { return }
        if elapsed >= 0.20 {
            rates[transfer.id] = Int64(Double(max(0, received - transfer.lastBytes)) / elapsed)
            transfer.lastSample = now
            transfer.lastBytes = received
            active[taskID] = transfer
        }
        items[index].received = received
        if expected > 0 { items[index].total = expected }
        if items[index].name.hasPrefix("download"), let response = task.response {
            items[index].name = DownloadFiles.filename(for: response, source: items[index].source)
        }
    }

    fileprivate func finished(task: URLSessionDownloadTask, at temporaryFile: URL) {
        let taskID = task.taskIdentifier
        guard let transfer = active[taskID], let index = index(for: transfer.id) else { return }

        do {
            guard let response = task.response as? HTTPURLResponse else { throw DownloadFailure.invalidResponse }
            guard (200..<300).contains(response.statusCode) else { throw DownloadFailure.httpStatus(response.statusCode) }
            guard response.statusCode != 206 || transfer.resumed else { throw DownloadFailure.invalidResponse }

            let stage = stagedFile(transfer.id)
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: temporaryFile, to: stage)
            items[index].name = DownloadFiles.filename(for: response, source: items[index].source)
            let bytes = (try? stage.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? items[index].received
            completeStaged(items[index], bytes: bytes, taskID: taskID)
        } catch {
            fail(taskID: taskID, with: error)
        }
    }

    private func completeStaged(_ item: DownloadItem, bytes: Int64, taskID: Int?) {
        guard let index = index(for: item.id) else { return }
        let stage = stagedFile(item.id)
        items[index].received = bytes
        items[index].total = bytes
        items[index].phase = .finishing
        rates.removeValue(forKey: item.id)
        persist()
        Task {
            let outcome = await Task.detached(priority: .utility) {
                Result { try DownloadFiles.move(stage, to: item.folder, filename: item.name) }
            }.value
            if let taskID { active.removeValue(forKey: taskID) }
            guard let index = self.index(for: item.id) else { return }
            switch outcome {
            case .success(let file):
                items[index].phase = .completed
                items[index].name = file.lastPathComponent
                items[index].savedFile = file
                items[index].hasResumeData = false
                clearCheckpoint(item.id)
            case .failure(let error):
                items[index].phase = .failed
                items[index].error = error.localizedDescription
            }
            persist()
            schedule()
        }
    }

    fileprivate func completed(task: URLSessionTask, with error: Error?) {
        let taskID = task.taskIdentifier
        guard let transfer = active[taskID], let index = index(for: transfer.id),
              items[index].phase == .downloading else { return }
        guard let error else {
            fail(taskID: taskID, with: DownloadFailure.invalidResponse)
            return
        }
        let checkpoint = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        fail(taskID: taskID, with: error, resumeData: checkpoint)
    }

    private func finishPausing(taskID: Int, data: Data?) {
        guard let transfer = active[taskID], let index = index(for: transfer.id),
              items[index].phase == .pausing else { return }
        active.removeValue(forKey: taskID)
        items[index].hasResumeData = saveCheckpoint(transfer.id, data: data)
        items[index].phase = .paused
        persist()
        schedule()
    }

    private func fail(taskID: Int, with error: Error, resumeData: Data? = nil) {
        guard let transfer = active.removeValue(forKey: taskID), let index = index(for: transfer.id) else { return }
        rates.removeValue(forKey: transfer.id)
        items[index].hasResumeData = saveCheckpoint(transfer.id, data: resumeData)
        items[index].phase = .failed
        items[index].error = error.localizedDescription
        persist()
        schedule()
    }

    private func index(for id: UUID) -> Int? { items.firstIndex { $0.id == id } }

    private func checkpoint(_ id: UUID) -> URL { storage.appending(path: id.uuidString + ".resume") }
    private func stagedFile(_ id: UUID) -> URL { storage.appending(path: id.uuidString + ".staging") }

    private func saveCheckpoint(_ id: UUID, data: Data?) -> Bool {
        guard let data, !data.isEmpty else {
            clearCheckpoint(id)
            return false
        }
        do {
            try OrbitStorage.write(data, to: checkpoint(id))
            return true
        } catch {
            clearCheckpoint(id)
            return false
        }
    }

    private func clearCheckpoint(_ id: UUID) {
        try? FileManager.default.removeItem(at: checkpoint(id))
    }

    private func persist() {
        do {
            try OrbitStorage.write(JSONEncoder().encode(items), to: storage.appending(path: "Queue.json"))
        } catch {
            persistenceError = "The download queue couldn’t be saved. \(error.localizedDescription)"
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var manager: DownloadManager?

    init(manager: DownloadManager) {
        self.manager = manager
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        MainActor.assumeIsolated {
            manager?.didWrite(task: downloadTask, received: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        MainActor.assumeIsolated {
            manager?.finished(task: downloadTask, at: location)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            manager?.completed(task: task, with: error)
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let scheme = request.url?.scheme?.lowercased()
        if scheme == "http" || scheme == "https" { completionHandler(request) }
        else { completionHandler(nil) }
    }
}
