import Foundation
import XCTest

final class ImportAccessTests: XCTestCase {
    @MainActor
    func testFolderAuthorizationIsReusedAndRestored() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let files = try makeFiles(["one.mp4", "第一 段.MOV"])
        let access = ImportAccessStore(defaults: defaults)
        var prompts = 0
        XCTAssertTrue(try access.authorize(files) { directory in prompts += 1; return directory })
        XCTAssertEqual(prompts, 1)
        XCTAssertTrue(try access.authorize(files) { _ in XCTFail("Do not ask again"); return nil })

        let restored = ImportAccessStore(defaults: defaults)
        XCTAssertTrue(try restored.authorize(files) { _ in XCTFail("Restore the saved grant"); return nil })
        XCTAssertEqual((defaults.array(forKey: ImportAccessStore.directoriesKey) as? [Data])?.count, 1)
    }

    @MainActor
    func testUnrelatedFoldersDoNotGrantAccess() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let files = try makeFiles(["one.mp4"])
        let parent = files[0].deletingLastPathComponent()
        let sibling = parent.appendingPathComponent("unrelated", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let access = ImportAccessStore(defaults: defaults)
        XCTAssertThrowsError(try access.authorize(files) { _ in sibling })
        XCTAssertFalse(try access.authorize(files) { _ in nil })
        XCTAssertNil(defaults.array(forKey: ImportAccessStore.directoriesKey))
    }

    @MainActor
    func testPreexistingWindowsMergeAndReuseDirectoryGrants() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = ImportAccessStore(defaults: defaults)
        let second = ImportAccessStore(defaults: defaults)
        let firstFiles = try makeFiles(["one.mp4"])
        let secondFiles = try makeFiles(["two.mp4"])
        XCTAssertTrue(try first.authorize(firstFiles) { $0 })
        XCTAssertTrue(try second.authorize(firstFiles) { _ in XCTFail("Reuse the other window's grant"); return nil })
        XCTAssertTrue(try second.authorize(secondFiles) { $0 })
        XCTAssertTrue(try first.authorize(secondFiles) { _ in XCTFail("Keep both windows' grants"); return nil })
        XCTAssertEqual((defaults.array(forKey: ImportAccessStore.directoriesKey) as? [Data])?.count, 2)
    }

    @MainActor
    func testGrantsSavedDuringTheAuthorizationPanelArePreserved() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = ImportAccessStore(defaults: defaults)
        let second = ImportAccessStore(defaults: defaults)
        let firstFiles = try makeFiles(["one.mp4"])
        let secondFiles = try makeFiles(["two.mp4"])
        XCTAssertTrue(try second.authorize(secondFiles) { directory in
            do {
                XCTAssertTrue(try first.authorize(firstFiles) { $0 })
            } catch { XCTFail("The other window could not save its grant: \(error)") }
            return directory
        })
        XCTAssertEqual((defaults.array(forKey: ImportAccessStore.directoriesKey) as? [Data])?.count, 2)
    }

    @MainActor
    func testSiblingPrefixesAndSymlinkEscapesNeedSeparateAuthorization() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let files = try makeFiles(["one.mp4"])
        let directory = files[0].deletingLastPathComponent()
        let sibling = URL(fileURLWithPath: directory.path + "-sibling", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let outside = sibling.appendingPathComponent("outside.mp4")
        try Data("Original test data".utf8).write(to: outside)
        let link = directory.appendingPathComponent("linked-folder", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sibling)
        let access = ImportAccessStore(defaults: defaults)
        XCTAssertTrue(try access.authorize(files) { $0 })
        XCTAssertFalse(try access.authorize([outside]) { _ in nil })
        XCTAssertFalse(try access.authorize([link.appendingPathComponent("outside.mp4")]) { _ in nil })
    }

    @MainActor
    func testUnavailableBookmarksArePreservedForLaterVolumeMounts() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let bookmark = Data("Unavailable bookmark".utf8)
        defaults.set([bookmark], forKey: ImportAccessStore.directoriesKey)
        _ = ImportAccessStore(defaults: defaults)
        XCTAssertEqual(defaults.array(forKey: ImportAccessStore.directoriesKey) as? [Data], [bookmark])
    }

    @MainActor
    func testFinderSelectionImportsTogetherAndCancellationPreservesQueue() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let files = try makeFiles(["one.mp4", "two.MOV"])
        var prompts = 0
        let store = BatchStore(defaults: defaults, importFolderChooser: { directory in
            prompts += 1
            return directory
        })
        store.importFromFinder(files)
        await waitForImports(store)
        XCTAssertEqual(Set(store.items.map(\.url)), Set(files))
        XCTAssertEqual(prompts, 1)
        store.importFromFinder(files)
        await waitForImports(store)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(prompts, 1)

        let cancelledFiles = try makeFiles(["cancelled.mp4"])
        let cancelled = BatchStore(defaults: defaults, importFolderChooser: { _ in nil })
        cancelled.items = store.items
        cancelled.selectedItemID = store.selectedItemID
        cancelled.importFromFinder(cancelledFiles)
        await waitForImports(cancelled)
        XCTAssertEqual(cancelled.items.map(\.id), store.items.map(\.id))
        XCTAssertEqual(cancelled.selectedItemID, store.selectedItemID)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "ImportAccessTests." + UUID().uuidString
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func makeFiles(_ names: [String]) throws -> [URL] {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"])
        let directory = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("import-access/\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try names.map { name in
            let url = directory.appendingPathComponent(name)
            try Data("Original test data".utf8).write(to: url)
            return url
        }
    }

    @MainActor
    private func waitForImports(_ store: BatchStore) async {
        let deadline = Date().addingTimeInterval(2)
        while store.isImporting, Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(store.isImporting)
    }
}
