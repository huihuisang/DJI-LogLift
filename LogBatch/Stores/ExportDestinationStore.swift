import Foundation

@MainActor
final class ExportDestinationStore {
    static let bookmarkKey = "export.outputDirectoryBookmark"
    private let defaults: UserDefaults
    private var scope: SecurityScope?

    enum Failure: Error {
        case unavailableDirectory
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func restore() -> URL? {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else {
            scope = nil
            return nil
        }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            let restoredScope = SecurityScope(url)
            guard Self.isUsable(url) else { throw Failure.unavailableDirectory }
            if stale {
                let refreshed = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                                    relativeTo: nil)
                if defaults.data(forKey: Self.bookmarkKey) == data { defaults.set(refreshed, forKey: Self.bookmarkKey) }
            }
            scope = restoredScope
            return url
        } catch {
            if defaults.data(forKey: Self.bookmarkKey) == data { defaults.removeObject(forKey: Self.bookmarkKey) }
            scope = nil
            return nil
        }
    }

    func remember(_ url: URL) throws {
        let selectedScope = SecurityScope(url)
        guard Self.isUsable(url) else { throw Failure.unavailableDirectory }
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: Self.bookmarkKey)
        scope = selectedScope
    }

    func access(_ url: URL) -> Bool {
        if scope?.url != url { scope = SecurityScope(url) }
        return Self.isUsable(url)
    }

    private static func isUsable(_ url: URL) -> Bool {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .volumeIsReadOnlyKey]),
              values.isDirectory == true, values.volumeIsReadOnly != true else { return false }
        return FileManager.default.isWritableFile(atPath: url.path)
    }
}
