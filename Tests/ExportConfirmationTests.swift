import Foundation
import XCTest

final class ExportConfirmationTests: XCTestCase {
    @MainActor
    func testRequestWaitsForConfirmationAndCancelDoesNotSaveSuppression() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = try makeStore(defaults: defaults)

        store.start()
        XCTAssertTrue(store.showsExportConfirmation)
        XCTAssertFalse(store.isProcessing)
        XCTAssertFalse(store.suppressExportReminder)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: store.outputDirectory!.path).isEmpty)

        store.suppressExportReminder = true
        store.start()
        XCTAssertTrue(store.suppressExportReminder)
        store.cancelExportConfirmation()
        XCTAssertFalse(store.showsExportConfirmation)
        XCTAssertFalse(defaults.bool(forKey: BatchStore.suppressExportReminderKey))
        store.start()
        XCTAssertTrue(store.showsExportConfirmation)
        XCTAssertFalse(store.suppressExportReminder)
        store.cancelExportConfirmation()
    }

    @MainActor
    func testConfirmationWithoutARequestDoesNotStartOrSaveSuppression() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = try makeStore(defaults: defaults)
        store.suppressExportReminder = true

        store.confirmExport()

        XCTAssertFalse(store.isProcessing)
        XCTAssertFalse(defaults.bool(forKey: BatchStore.suppressExportReminderKey))
    }

    @MainActor
    func testConfirmationExportsAndUnselectedSuppressionStillPromptsNextTime() async throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = try makeStore(defaults: defaults)
        store.start()
        // SwiftUI can dismiss the dialog binding before it calls the selected action.
        store.showsExportConfirmation = false
        store.confirmExport()
        XCTAssertTrue(store.isProcessing)
        try await waitForExport(store)
        XCTAssertEqual(store.items.first?.status, .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(store.items.first?.output).path))
        XCTAssertFalse(defaults.bool(forKey: BatchStore.suppressExportReminderKey))

        store.items.append(BatchItem(url: try XCTUnwrap(store.items.first?.url)))
        store.start()
        XCTAssertTrue(store.showsExportConfirmation)
        XCTAssertFalse(store.isProcessing)
        store.cancelExportConfirmation()
    }

    @MainActor
    func testConfirmedSuppressionIsSharedAcrossInstancesAndCameraChanges() async throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let first = try makeStore(defaults: defaults)
        let existingWindow = try makeStore(defaults: defaults)
        first.start()
        first.suppressExportReminder = true
        first.confirmExport()
        try await waitForExport(first)
        XCTAssertEqual(first.items.first?.status, .completed)
        XCTAssertTrue(defaults.bool(forKey: BatchStore.suppressExportReminderKey))

        existingWindow.selectedProductID = "osmo-pocket-3"
        existingWindow.selectCamera()
        existingWindow.start()
        XCTAssertFalse(existingWindow.showsExportConfirmation)
        XCTAssertTrue(existingWindow.isProcessing)
        try await waitForExport(existingWindow)
        XCTAssertEqual(existingWindow.items.first?.status, .completed)

        let reopened = try makeStore(defaults: UserDefaults(suiteName: domain)!)
        reopened.start()
        XCTAssertFalse(reopened.showsExportConfirmation)
        XCTAssertTrue(reopened.isProcessing)
        try await waitForExport(reopened)
        XCTAssertEqual(reopened.items.first?.status, .completed)
    }

    @MainActor
    func testInvalidExportConditionsNeverPromptOrStart() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        for condition in ["empty", "completed", "lut", "importing", "processing"] {
            let store = try makeStore(defaults: defaults)
            switch condition {
            case "empty": store.items = []
            case "completed": store.items[0].status = .completed
            case "lut": store.selectedLUTID = nil
            case "importing": store.isImporting = true
            case "processing": store.isProcessing = true
            default: XCTFail("Unexpected test condition")
            }
            XCTAssertFalse(store.canStart, condition)
            store.start()
            XCTAssertFalse(store.showsExportConfirmation, condition)
            XCTAssertEqual(store.isProcessing, condition == "processing")
        }
    }

    @MainActor
    func testConfirmationRechecksEligibilityAndCameraChangesInvalidateTheRequest() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = try makeStore(defaults: defaults)
        let directory = store.outputDirectory
        store.start()
        store.suppressExportReminder = true
        store.outputDirectory = nil
        store.confirmExport()
        XCTAssertFalse(store.isProcessing)
        XCTAssertFalse(store.showsExportConfirmation)
        XCTAssertFalse(defaults.bool(forKey: BatchStore.suppressExportReminderKey))

        store.outputDirectory = directory
        store.start()
        store.selectCamera()
        store.confirmExport()
        XCTAssertFalse(store.isProcessing)
        XCTAssertFalse(store.showsExportConfirmation)
    }

    @MainActor
    private func makeStore(defaults: UserDefaults) throws -> BatchStore {
        let root = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"]))
        let output = root.appendingPathComponent("export-confirmation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = BatchStore(defaults: defaults)
        store.items = [BatchItem(url: root.appendingPathComponent("synthetic.mp4"))]
        store.outputDirectory = output
        return store
    }

    @MainActor
    private func waitForExport(_ store: BatchStore) async throws {
        let deadline = Date().addingTimeInterval(15)
        while store.isProcessing && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        if store.isProcessing { store.cancel() }
        XCTAssertFalse(store.isProcessing, "Export did not finish before the timeout")
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let domain = "LogBatchTests.ExportConfirmation." + UUID().uuidString
        return (UserDefaults(suiteName: domain)!, domain)
    }
}
