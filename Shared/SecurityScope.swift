import Foundation

final class SecurityScope: Sendable {
    let url: URL
    let active: Bool

    init(_ url: URL) {
        self.url = url
        active = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if active { url.stopAccessingSecurityScopedResource() }
    }
}
