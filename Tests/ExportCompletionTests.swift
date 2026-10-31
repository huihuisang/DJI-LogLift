import Foundation
import XCTest

final class ExportCompletionTests: XCTestCase {
    @MainActor
    func testSuccessfulBatchNotifiesOnceAndResetsFeedbackAfterTwoSeconds() async throws {
        let spy = CompletionNotificationSpy()
        let store = try makeStore(notifications: spy)
        var old = BatchItem(url: URL(fileURLWithPath: "/previously-exported.mp4"))
        old.status = .completed
        store.items.insert(old, at: 0)
        store.start()
        try await waitForExport(store)
        XCTAssertTrue(store.showsExportSuccess)
        XCTAssertTrue(store.items.allSatisfy { $0.status == .completed })
        XCTAssertFalse(store.canStart)
        XCTAssertEqual(spy.authorizationRequests, 1)
        XCTAssertEqual(spy.completions.count, 1)
        XCTAssertEqual(spy.completions.first?.count, 1)
        XCTAssertEqual(spy.completions.first?.directory, store.outputDirectory)

        try await Task.sleep(for: .milliseconds(2200))

        XCTAssertFalse(store.showsExportSuccess)
        XCTAssertTrue(store.items.allSatisfy { $0.status == .completed })
        XCTAssertFalse(store.canStart)
        XCTAssertEqual(spy.completions.count, 1)
    }

    @MainActor
    func testPartialFailureAndCancellationDoNotReportSuccess() async throws {
        let failedSpy = CompletionNotificationSpy()
        let failed = try makeStore(notifications: failedSpy)
        failed.items.append(BatchItem(url: URL(fileURLWithPath: "/missing-\(UUID().uuidString).mp4")))
        failed.start()
        try await waitForExport(failed)
        XCTAssertEqual(failed.items[0].status, .completed)
        XCTAssertEqual(failed.items[1].status, .failed)
        XCTAssertFalse(failed.showsExportSuccess)
        XCTAssertTrue(failedSpy.completions.isEmpty)

        let cancelledSpy = CompletionNotificationSpy()
        let cancelled = try makeStore(notifications: cancelledSpy)
        cancelled.start()
        cancelled.cancel()
        try await waitForExport(cancelled)
        XCTAssertFalse(cancelled.showsExportSuccess)
        XCTAssertTrue(cancelledSpy.completions.isEmpty)
    }

    @MainActor
    func testOldResetCannotClearNewBatchFeedbackAndClearEndsFeedback() async throws {
        let spy = CompletionNotificationSpy()
        let store = try makeStore(notifications: spy)
        store.start()
        try await waitForExport(store)
        try await Task.sleep(for: .milliseconds(1200))
        let nextDirectory = try XCTUnwrap(store.outputDirectory).appendingPathComponent("next")
        try FileManager.default.createDirectory(at: nextDirectory, withIntermediateDirectories: true)
        store.outputDirectory = nextDirectory
        store.items.append(BatchItem(url: try XCTUnwrap(store.items.first?.url)))
        store.start()
        XCTAssertFalse(store.showsExportSuccess)
        try await waitForExport(store)
        XCTAssertTrue(store.showsExportSuccess)

        try await Task.sleep(for: .milliseconds(1000))

        XCTAssertTrue(store.showsExportSuccess)
        XCTAssertEqual(spy.completions.count, 2)
        store.clear()
        XCTAssertFalse(store.showsExportSuccess)
        XCTAssertTrue(store.items.isEmpty)
    }

    @MainActor
    func testNotificationContentContainsBatchCountAndDestination() {
        let destination = URL(fileURLWithPath: "/Movies/Completion-Output")
        for count in [1, 3] {
            let content = ExportNotifications.content(count: count, directory: destination)
            XCTAssertFalse(content.title.isEmpty)
            XCTAssertTrue(content.body.contains(String(count)))
            XCTAssertTrue(content.body.contains(destination.lastPathComponent))
            XCTAssertEqual(content.threadIdentifier, "export-completion")
            XCTAssertNotNil(content.sound)
        }
    }

    @MainActor
    private func makeStore(notifications: CompletionNotificationSpy) throws -> BatchStore {
        let domain = "LogBatchTests.ExportCompletion." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defaults.set(true, forKey: BatchStore.suppressExportReminderKey)
        addTeardownBlock { defaults.removePersistentDomain(forName: domain) }
        let root = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"]))
        let directory = root.appendingPathComponent("completion-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = BatchStore(defaults: defaults, notifications: notifications)
        store.items = [BatchItem(url: root.appendingPathComponent("synthetic.mp4"))]
        store.outputDirectory = directory
        return store
    }

    @MainActor
    private func waitForExport(_ store: BatchStore) async throws {
        let deadline = Date().addingTimeInterval(15)
        while store.isProcessing && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(store.isProcessing)
        await Task.yield()
    }
}

@MainActor
private final class CompletionNotificationSpy: ExportNotifying {
    var authorizationRequests = 0
    var completions = [(count: Int, directory: URL)]()

    func requestAuthorization() { authorizationRequests += 1 }
    func exportCompleted(count: Int, directory: URL) async { completions.append((count, directory)) }
}
