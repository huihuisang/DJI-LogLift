import Foundation
import XCTest

final class ExternalImportTests: XCTestCase {
    @MainActor
    func testConsecutiveOpenEventsImportEveryFileOnce() async throws {
        let files = try makeFiles(["First.MOV", "second.mp4", "third.m4v"])
        let store = BatchStore()

        store.add([files[0]])
        store.add([files[1], files[2]])
        store.add([files[0]])

        await waitForImports(store, count: 3)
        XCTAssertEqual(Set(store.items.map(\.url)), Set(files))
        XCTAssertEqual(store.items.count, 3)
        XCTAssertNotNil(store.selectedItemID)
    }

    @MainActor
    func testOpenEventsWaitUntilConversionEnds() async throws {
        let files = try makeFiles(["one.mp4", "two.mov"])
        let store = BatchStore()
        let existing = BatchItem(url: files[0])
        store.items = [existing]
        store.selectedItemID = existing.id
        store.isProcessing = true

        store.add(files)
        XCTAssertEqual(store.items.map(\.id), [existing.id])
        XCTAssertFalse(store.isImporting)
        store.isProcessing = false

        await waitForImports(store, count: 2)
        XCTAssertEqual(Set(store.items.map(\.url)), Set(files))
        XCTAssertEqual(store.selectedItemID, existing.id)
    }

    @MainActor
    func testImportRejectsRemoteMissingAndUnsupportedFiles() async throws {
        let files = try makeFiles(["one.mp4", "notes.txt"])
        let store = BatchStore()
        store.add(files + [URL(string: "https://example.com/movie.mp4")!,
                           files[0].deletingLastPathComponent().appendingPathComponent("missing.mov")])

        await waitForImports(store, count: 1)
        XCTAssertEqual(store.items.map(\.url), [files[0]])
    }

    private func makeFiles(_ names: [String]) throws -> [URL] {
        let base = try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"])
        let root = URL(fileURLWithPath: base, isDirectory: true)
            .appendingPathComponent("external-import/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try names.map { name in
            let url = root.appendingPathComponent(name)
            try Data("Original test data".utf8).write(to: url)
            return url
        }
    }

    @MainActor
    private func waitForImports(_ store: BatchStore, count: Int) async {
        let deadline = Date().addingTimeInterval(2)
        while (store.isImporting || store.items.count < count), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(store.isImporting)
    }
}
