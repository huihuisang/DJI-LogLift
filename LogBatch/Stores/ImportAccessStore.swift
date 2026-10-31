import Foundation

@MainActor
final class ImportAccessStore {
    static let directoriesKey = "import.readableDirectories"

    enum Failure: LocalizedError {
        case unrelatedFolder

        var errorDescription: String? {
            String(localized: "The selected folder does not contain the requested videos.")
        }
    }

    private struct Grant {
        let scope: SecurityScope
        let bookmark: Data
    }

    private let defaults: UserDefaults
    private var grants = [Grant]()
    private var bookmarks: [Data]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bookmarks = []
        reload()
    }

    private func reload() {
        bookmarks = defaults.array(forKey: Self.directoriesKey) as? [Data] ?? []
        var restored = [Grant]()
        var refreshed = false
        for (index, data) in bookmarks.enumerated() {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                     relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
            let scope = SecurityScope(url)
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let bookmark = stale ? (try? Self.bookmark(for: url)) : data
            if let bookmark {
                restored.append(Grant(scope: scope, bookmark: bookmark))
                if stale { bookmarks[index] = bookmark; refreshed = true }
            }
        }
        grants = restored
        if refreshed { persist() }
    }

    func authorize(_ files: [URL], chooseFolder: (URL) -> URL?) throws -> Bool {
        reload()
        for file in files where !canRead(file) {
            let parent = file.deletingLastPathComponent()
            guard let chosen = chooseFolder(parent) else { return false }
            let scope = SecurityScope(chosen)
            guard (try? chosen.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  Self.contains(file, in: chosen) else { throw Failure.unrelatedFolder }
            let bookmark = try Self.bookmark(for: chosen)
            // A different window can save a grant while the open panel runs its nested event loop.
            reload()
            let superseded = Set(grants.filter { Self.contains($0.scope.url, in: chosen) }.map(\.bookmark))
            bookmarks.removeAll { superseded.contains($0) }
            grants.removeAll { superseded.contains($0.bookmark) }
            grants.append(Grant(scope: scope, bookmark: bookmark))
            bookmarks.append(bookmark)
            persist()
            guard canRead(file) else { throw CocoaError(.fileReadNoPermission) }
        }
        return true
    }

    private func canRead(_ file: URL) -> Bool {
        guard grants.contains(where: { Self.contains(file, in: $0.scope.url) }),
              let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1)) != nil
    }

    private static func contains(_ file: URL, in directory: URL) -> Bool {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let path = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return path.starts(with: root)
    }

    private static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                             includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func persist() {
        defaults.set(bookmarks, forKey: Self.directoriesKey)
    }
}
