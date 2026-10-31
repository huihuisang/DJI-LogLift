import Foundation
import OSLog
import UserNotifications

@MainActor
protocol ExportNotifying: AnyObject {
    func requestAuthorization()
    func exportCompleted(count: Int, directory: URL) async
}

@MainActor
final class ExportNotifications: NSObject, ExportNotifying, UNUserNotificationCenterDelegate {
    static let shared = ExportNotifications()
    private static let logger = Logger(subsystem: "dev.logbatch.app", category: "ExportNotifications")
    private var authorizationTask: Task<Void, Never>?
    private lazy var center: UNUserNotificationCenter = {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }()

    func requestAuthorization() {
        guard authorizationTask == nil else { return }
        let center = center
        authorizationTask = Task { [weak self] in
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            self?.authorizationTask = nil
        }
    }

    func exportCompleted(count: Int, directory: URL) async {
        guard count > 0 else { return }
        requestAuthorization()
        await authorizationTask?.value
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: Self.content(count: count, directory: directory), trigger: nil)
        do {
            try await center.add(request)
        } catch {
            Self.logger.error("Could not deliver the export notification: \(error.localizedDescription)")
        }
    }

    static func content(count: Int, directory: URL) -> UNMutableNotificationContent {
        let bundle = Bundle(for: ExportNotifications.self)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Export complete", bundle: bundle)
        if count == 1 {
            content.body = String(localized: "1 video was saved to \(directory.lastPathComponent).", bundle: bundle)
        } else {
            content.body = String(localized: "\(count) videos were saved to \(directory.lastPathComponent).", bundle: bundle)
        }
        content.sound = .default
        content.threadIdentifier = "export-completion"
        return content
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
