import AppKit
import Darwin
import FinderSync
import OSLog

@MainActor
final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        Self.updateMonitoredDirectories()
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(volumesChanged),
                                                               name: name, object: nil)
        }
    }

    @objc nonisolated private func volumesChanged(_ notification: Notification) {
        Self.updateMonitoredDirectories()
    }

    nonisolated private static func updateMonitoredDirectories() {
        var directories: Set<URL> = [URL(fileURLWithPath: "/", isDirectory: true),
                                     URL(fileURLWithPath: "/Volumes", isDirectory: true)]
        directories.formUnion(FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                                     options: [.skipHiddenVolumes]) ?? [])
        if let path = getpwuid(getuid())?.pointee.pw_dir {
            let home = URL(fileURLWithPath: String(cString: path), isDirectory: true)
            directories.insert(home)
            for folder in ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Public",
                           "Library/CloudStorage", "Library/Mobile Documents"] {
                directories.insert(home.appendingPathComponent(folder, isDirectory: true))
            }
        }
        FIFinderSyncController.default().directoryURLs = directories
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              !VideoFiles.requestedSelection(from: FIFinderSyncController.default().selectedItemURLs() ?? []).isEmpty else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: String(localized: "Import into LogLift"),
                              action: #selector(importVideos), keyEquivalent: "")
        item.target = self
        item.image = FinderMenuIcon.applicationIcon(in: Bundle(for: FinderSync.self))
        menu.addItem(item)
        return menu
    }

    @objc nonisolated private func importVideos() {
        // Finder invokes this action on its XPC queue. Capture the selection before leaving the callback.
        let selection = FIFinderSyncController.default().selectedItemURLs() ?? []
        let urls = VideoFiles.requestedSelection(from: selection)
        guard !urls.isEmpty, let app = ContainingApplication.url(forExtensionAt: Bundle.main.bundleURL) else { return }
        Task { @MainActor in
            do {
                let requestURL = try FinderImportRequest.publish(urls)
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                configuration.allowsRunningApplicationSubstitution = false
                NSWorkspace.shared.open([requestURL], withApplicationAt: app, configuration: configuration) { _, error in
                    guard let error else { return }
                    let failure = error as NSError
                    Logger(subsystem: "dev.logbatch.app.FinderExtension", category: "Import")
                        .error("Opening the app failed: \(failure.domain, privacy: .public) \(failure.code)")
                    Task { @MainActor in
                        FinderImportRequest.discard(requestURL)
                        Self.showError(error)
                    }
                }
            } catch { Self.showError(error) }
        }
    }

    private static func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = String(localized: "LogLift could not be opened.")
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
