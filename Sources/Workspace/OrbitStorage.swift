import Foundation

enum OrbitStorage {
    static var appSupport: URL {
        URL.applicationSupportDirectory.appending(path: "Orbit", directoryHint: .isDirectory)
    }

    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
