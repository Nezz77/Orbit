import Foundation
import UniformTypeIdentifiers

enum DownloadFailure: LocalizedError {
    case invalidLink
    case duplicate
    case missingFolder
    case invalidResponse
    case httpStatus(Int)
    case noFreeFilename

    var errorDescription: String? {
        switch self {
        case .invalidLink: "Enter a direct HTTP or HTTPS file link."
        case .duplicate: "That link is already in the queue."
        case .missingFolder: "The download folder is unavailable. Choose another folder and add the link again."
        case .invalidResponse: "The server’s response didn’t contain a complete file."
        case .httpStatus(let status): "The server returned HTTP \(status)."
        case .noFreeFilename: "Orbit couldn’t find an available filename in this folder."
        }
    }
}

enum DownloadFiles {
    static func validatedURL(_ text: String) -> URL? {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        var withoutFragment = components
        withoutFragment.fragment = nil
        return withoutFragment.url
    }

    static func filename(for response: URLResponse?, source: URL) -> String {
        // Like Prism, use the server's name before the URL and add an extension from the MIME type when useful.
        let rawName = response?.suggestedFilename ?? source.lastPathComponent
        let safeScalars = rawName.unicodeScalars.map { scalar -> String in
            if CharacterSet.controlCharacters.contains(scalar)
                || CharacterSet.illegalCharacters.contains(scalar)
                || "/\\:".unicodeScalars.contains(scalar)
                || (0x202A...0x202E).contains(scalar.value)
                || (0x2066...0x2069).contains(scalar.value) {
                return "_"
            }
            return String(scalar)
        }
        let initial = safeScalars.joined().trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        var fullName = initial.isEmpty ? "download" : initial
        if (fullName as NSString).pathExtension.isEmpty,
           let mime = response?.mimeType, mime != "application/octet-stream",
           let suffix = UTType(mimeType: mime)?.preferredFilenameExtension {
            fullName += "." + suffix
        }
        let path = fullName as NSString
        let suffix = path.pathExtension
        let extensionPart = suffix.utf8.count < 32 && !suffix.isEmpty ? "." + suffix : ""
        let base = extensionPart.isEmpty ? fullName : path.deletingPathExtension
        var shortened = ""
        var bytes = 0
        for character in base {
            let count = String(character).utf8.count
            guard bytes + count <= 200 - extensionPart.utf8.count else { break }
            shortened.append(character)
            bytes += count
        }
        return (shortened.isEmpty ? "download" : shortened) + extensionPart
    }

    static func move(_ source: URL, to folder: URL, filename: String) throws -> URL {
        let values = try? folder.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else { throw DownloadFailure.missingFolder }
        let file = filename as NSString
        let suffix = file.pathExtension
        let base = file.deletingPathExtension

        for attempt in 0..<1000 {
            let name = attempt == 0 ? filename : base + " (\(attempt))" + (suffix.isEmpty ? "" : "." + suffix)
            let target = folder.appending(path: name, directoryHint: .notDirectory)
            do {
                try FileManager.default.moveItem(at: source, to: target)
                return target
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw DownloadFailure.noFreeFilename
    }
}
