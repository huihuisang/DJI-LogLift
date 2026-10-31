import Foundation
import XCTest

final class ExportDestinationTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testExportWithoutFolderChoosesAndRemembersBeforeConfirmation() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let folder = try makeFolder()
        var choices = 0
        let store = BatchStore(defaults: defaults, outputFolderChooser: { _ in choices += 1; return folder })
        store.items = [BatchItem(url: folder.appendingPathComponent("source.mp4"))]

        XCTAssertNil(store.outputDirectory)
        XCTAssertTrue(store.canStart)
        store.start()

        XCTAssertEqual(choices, 1)
        XCTAssertEqual(store.outputDirectory, folder)
        XCTAssertTrue(store.showsExportConfirmation)
        XCTAssertFalse(store.isProcessing)
        XCTAssertNotNil(defaults.data(forKey: ExportDestinationStore.bookmarkKey))

        let reopened = BatchStore(defaults: UserDefaults(suiteName: domain)!, outputFolderChooser: { _ in
            XCTFail("A restored directory must not reopen the picker")
            return nil
        })
        XCTAssertEqual(reopened.outputDirectory, folder)
        reopened.items = store.items
        reopened.start()
        XCTAssertTrue(reopened.showsExportConfirmation)
        store.cancelExportConfirmation()
        reopened.cancelExportConfirmation()
    }

    @MainActor
    func testCancellingFolderSelectionDoesNotStartOrChangePreferences() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        var choices = 0
        let store = BatchStore(defaults: defaults, outputFolderChooser: { _ in choices += 1; return nil })
        store.items = [BatchItem(url: URL(fileURLWithPath: "/source.mp4"))]
        store.start()
        XCTAssertEqual(choices, 1)
        XCTAssertNil(store.outputDirectory)
        XCTAssertFalse(store.showsExportConfirmation)
        XCTAssertFalse(store.isProcessing)
        XCTAssertNil(defaults.object(forKey: ExportDestinationStore.bookmarkKey))
        XCTAssertFalse(defaults.bool(forKey: BatchStore.suppressExportReminderKey))
    }

    @MainActor
    func testCorruptBookmarkIsDiscardedAndFolderCanBeChosenAgain() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(Data("Invalid bookmark".utf8), forKey: ExportDestinationStore.bookmarkKey)
        let folder = try makeFolder()
        let store = BatchStore(defaults: defaults, outputFolderChooser: { _ in folder })
        XCTAssertNil(store.outputDirectory)
        XCTAssertNil(defaults.data(forKey: ExportDestinationStore.bookmarkKey))
        store.items = [BatchItem(url: folder.appendingPathComponent("source.mp4"))]
        store.start()
        XCTAssertEqual(store.outputDirectory, folder)
        XCTAssertTrue(store.showsExportConfirmation)
        store.cancelExportConfirmation()
    }

    @MainActor
    func testDeletedFolderRequiresSelectionAndCancellationDoesNotExport() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let folder = try makeFolder()
        let destinations = ExportDestinationStore(defaults: defaults)
        try destinations.remember(folder)
        var choices = 0
        let store = BatchStore(defaults: defaults, outputFolderChooser: { _ in choices += 1; return nil })
        try FileManager.default.removeItem(at: folder)
        store.items = [BatchItem(url: URL(fileURLWithPath: "/source.mp4"))]
        store.start()
        XCTAssertEqual(choices, 1)
        XCTAssertNil(store.outputDirectory)
        XCTAssertFalse(store.showsExportConfirmation)
        XCTAssertFalse(store.isProcessing)
    }

    @MainActor
    func testInvalidReplacementKeepsTheRememberedFolder() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let folder = try makeFolder()
        let destinations = ExportDestinationStore(defaults: defaults)
        try destinations.remember(folder)
        let saved = defaults.data(forKey: ExportDestinationStore.bookmarkKey)
        let file = folder.appendingPathComponent("file.txt")
        try Data("Test file".utf8).write(to: file)
        XCTAssertThrowsError(try destinations.remember(file))
        XCTAssertEqual(defaults.data(forKey: ExportDestinationStore.bookmarkKey), saved)
        XCTAssertEqual(ExportDestinationStore(defaults: defaults).restore(), folder)
    }

    @MainActor
    func testClearingQueueKeepsDirectoryAndAnExistingWindowUsesTheCache() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let folder = try makeFolder()
        let existing = BatchStore(defaults: defaults, outputFolderChooser: { _ in
            XCTFail("An existing window must reuse the newly saved folder")
            return nil
        })
        let first = BatchStore(defaults: defaults, outputFolderChooser: { _ in folder })
        XCTAssertTrue(first.chooseOutput())
        first.clear()
        XCTAssertEqual(first.outputDirectory, folder)
        existing.items = [BatchItem(url: folder.appendingPathComponent("source.mp4"))]
        existing.start()
        XCTAssertEqual(existing.outputDirectory, folder)
        XCTAssertTrue(existing.showsExportConfirmation)
        existing.cancelExportConfirmation()
    }

    @MainActor
    func testRenamedFolderRestoresAtItsNewLocation() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let folder = try makeFolder()
        let destinations = ExportDestinationStore(defaults: defaults)
        try destinations.remember(folder)
        let moved = folder.deletingLastPathComponent().appendingPathComponent("renamed-" + UUID().uuidString,
                                                                              isDirectory: true).standardizedFileURL
        try FileManager.default.moveItem(at: folder, to: moved)
        XCTAssertEqual(ExportDestinationStore(defaults: defaults).restore(), moved)
        XCTAssertEqual(ExportDestinationStore(defaults: UserDefaults(suiteName: domain)!).restore(), moved)
    }

    @MainActor
    func testReadOnlyFolderIsNotRestored() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let folder = try makeFolder()
        try ExportDestinationStore(defaults: defaults).remember(folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        XCTAssertNil(ExportDestinationStore(defaults: defaults).restore())
        XCTAssertNil(defaults.data(forKey: ExportDestinationStore.bookmarkKey))
    }

    @MainActor
    func testCancellingReplacementKeepsThePreviousChoice() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let folder = try makeFolder()
        try ExportDestinationStore(defaults: defaults).remember(folder)
        let saved = defaults.data(forKey: ExportDestinationStore.bookmarkKey)
        let store = BatchStore(defaults: defaults, outputFolderChooser: { current in
            XCTAssertEqual(current, folder)
            return nil
        })
        XCTAssertFalse(store.chooseOutput())
        XCTAssertEqual(store.outputDirectory, folder)
        XCTAssertEqual(defaults.data(forKey: ExportDestinationStore.bookmarkKey), saved)
    }

    @MainActor
    func testFirstExportChoosesFolderAndContinuesWithoutReminderWhenSuppressed() async throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: BatchStore.suppressExportReminderKey)
        let folder = try makeFolder()
        let root = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"]))
        var choices = 0
        let store = BatchStore(defaults: defaults, outputFolderChooser: { _ in choices += 1; return folder })
        store.items = [BatchItem(url: root.appendingPathComponent("synthetic.mp4"))]
        store.start()
        XCTAssertEqual(choices, 1)
        XCTAssertTrue(store.isProcessing)
        XCTAssertFalse(store.showsExportConfirmation)
        let deadline = Date().addingTimeInterval(15)
        while store.isProcessing, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        if store.isProcessing { store.cancel() }
        XCTAssertFalse(store.isProcessing)
        XCTAssertEqual(store.items.first?.status, .completed)
        XCTAssertEqual(store.items.first?.output?.deletingLastPathComponent().standardizedFileURL, folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("synthetic-rec709.mp4").path))
    }

    private func makeFolder() throws -> URL {
        let root = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"]))
        let folder = root.appendingPathComponent("export-destination-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.standardizedFileURL
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let domain = "LogBatchTests.ExportDestination." + UUID().uuidString
        return (UserDefaults(suiteName: domain)!, domain)
    }
}
