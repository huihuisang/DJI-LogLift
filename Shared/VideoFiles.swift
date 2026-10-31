import Foundation

enum VideoFiles {
    static let extensions: Set<String> = ["mov", "mp4", "m4v"]

    static func isCandidate(_ url: URL) -> Bool {
        url.isFileURL && (url.host?.isEmpty != false || url.host == "localhost")
            && !url.hasDirectoryPath && extensions.contains(url.pathExtension.lowercased())
    }

    static func requestedSelection(from urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { isCandidate($0) && seen.insert($0.standardizedFileURL).inserted }
    }

    static func supports(_ url: URL) -> Bool {
        guard isCandidate(url),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    static func selection(from urls: [URL]) -> [URL] {
        requestedSelection(from: urls).filter(supports)
    }
}
