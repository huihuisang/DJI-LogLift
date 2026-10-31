import Foundation

enum ContainingApplication {
    static func url(forExtensionAt extensionURL: URL) -> URL? {
        guard extensionURL.isFileURL, extensionURL.pathExtension == "appex" else { return nil }
        let plugins = extensionURL.deletingLastPathComponent()
        let contents = plugins.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard plugins.lastPathComponent == "PlugIns", contents.lastPathComponent == "Contents",
              app.pathExtension == "app" else { return nil }
        return app
    }
}
