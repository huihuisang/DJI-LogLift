import AppKit
import Foundation

struct FinderImportRequest: Codable, Sendable {
    static let scheme = "loglift"
    static let maximumFileCount = 10_000
    static let maximumBytes = 8 * 1024 * 1024
    private static let type = NSPasteboard.PasteboardType("dev.logbatch.video-import")
    private static let prefix = "dev.logbatch.import."

    var version = 1
    var createdAt = Date()
    let files: [URL]

    enum Failure: LocalizedError {
        case invalidRequest

        var errorDescription: String? {
            String(localized: "The Finder import request is invalid. Try again from Finder.")
        }
    }

    static func publish(_ files: [URL]) throws -> URL {
        let request = FinderImportRequest(files: files)
        try request.validate()
        let data = try JSONEncoder().encode(request)
        guard data.count <= maximumBytes else { throw Failure.invalidRequest }
        let token = UUID().uuidString
        let board = NSPasteboard(name: .init(prefix + token))
        board.declareTypes([type], owner: nil)
        guard board.setData(data, forType: type) else {
            board.releaseGlobally()
            throw Failure.invalidRequest
        }
        return URL(string: "\(scheme)://import?request=\(token)")!
    }

    static func consume(_ url: URL) throws -> FinderImportRequest {
        let board = try pasteboard(for: url)
        defer { board.releaseGlobally() }
        guard let data = board.data(forType: type), data.count <= maximumBytes else { throw Failure.invalidRequest }
        let request = try JSONDecoder().decode(Self.self, from: data)
        try request.validate()
        return request
    }

    static func discard(_ url: URL) {
        try? pasteboard(for: url).releaseGlobally()
    }

    private func validate() throws {
        let age = Date().timeIntervalSince(createdAt)
        guard version == 1, (-60...600).contains(age), !files.isEmpty, files.count <= Self.maximumFileCount,
              files.allSatisfy(VideoFiles.isCandidate) else { throw Failure.invalidRequest }
    }

    private static func pasteboard(for url: URL) throws -> NSPasteboard {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == scheme, parts.host == "import", parts.user == nil, parts.password == nil,
              parts.port == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/",
              let query = parts.queryItems, query.count == 1, query[0].name == "request",
              let token = query[0].value, UUID(uuidString: token) != nil else { throw Failure.invalidRequest }
        return NSPasteboard(name: .init(prefix + token))
    }
}
