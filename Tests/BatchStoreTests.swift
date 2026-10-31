import Foundation
import XCTest

final class BatchStoreTests: XCTestCase {
    @MainActor
    func testExportIsAvailableWithoutAnInspectorCheckbox() {
        let store = makeStore()
        store.outputDirectory = URL(fileURLWithPath: "/Movies/LogBatch")

        XCTAssertTrue(store.canStart)
    }

    @MainActor
    func testSelectionIgnoresBlankSpaceAndUnknownClips() {
        let store = makeStore()
        let selected = store.items[1].id
        store.selectItem(selected)

        store.selectItem(nil)
        XCTAssertEqual(store.selectedItemID, selected)
        store.selectItem(UUID())
        XCTAssertEqual(store.selectedItemID, selected)
        store.selectItem(store.items[2].id)
        XCTAssertEqual(store.selectedItemID, store.items[2].id)
    }

    @MainActor
    func testRemovingSelectedClipSelectsNextThenPreviousClip() {
        let store = makeStore()
        let first = store.items[0].id
        let middle = store.items[1].id
        let last = store.items[2].id
        store.selectItem(middle)

        store.remove(middle)
        XCTAssertEqual(store.selectedItemID, last)
        XCTAssertEqual(store.items.map(\.id), [first, last])

        store.remove(last)
        XCTAssertEqual(store.selectedItemID, first)
        store.remove(first)
        XCTAssertNil(store.selectedItemID)
        XCTAssertTrue(store.items.isEmpty)
    }

    @MainActor
    func testRemovingOtherOrUnknownClipPreservesSelection() {
        let store = makeStore()
        let selected = store.items[1].id
        store.selectItem(selected)
        store.remove(store.items[0].id)
        XCTAssertEqual(store.selectedItemID, selected)
        store.remove(UUID())
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.selectedItemID, selected)
    }

    @MainActor
    func testRemovingSelectedClipAndClearingResetPreviewState() {
        let store = makeStore()
        store.previewError = "Preview failed"
        store.isLoadingPreview = true
        store.remove(store.selectedItemID!)
        XCTAssertNil(store.previewError)
        XCTAssertFalse(store.isLoadingPreview)

        store.previewError = "Preview failed"
        store.isLoadingPreview = true
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.selectedItemID)
        XCTAssertNil(store.preview)
        XCTAssertNil(store.previewError)
        XCTAssertFalse(store.isLoadingPreview)
    }

    @MainActor
    func testQueueCannotChangeDuringImportOrConversion() {
        let store = makeStore()
        let selected = store.selectedItemID
        for importing in [false, true] {
            store.isImporting = importing
            store.isProcessing = !importing
            store.remove(store.items[0].id)
            store.clear()
            XCTAssertEqual(store.items.count, 3)
            XCTAssertEqual(store.selectedItemID, selected)
        }
    }

    @MainActor
    func testClipDetailsLoadThumbnailAndEmbeddedRecordingDate() async throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"])
        let source = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("synthetic-created.mp4")
        let store = BatchStore()
        store.items = [BatchItem(url: source)]

        await store.loadClipDetails(for: store.items[0].id)

        let item = try XCTUnwrap(store.items.first)
        XCTAssertTrue(item.hasLoadedDetails)
        XCTAssertNotNil(item.thumbnail)
        XCTAssertEqual(item.recordingDate, ISO8601DateFormatter().date(from: "2026-10-29T02:30:00Z"))
    }

    @MainActor
    func testMissingClipDetailsFinishWithUnknownDateAndPlaceholder() async {
        let store = BatchStore()
        store.items = [BatchItem(url: URL(fileURLWithPath: "/missing-\(UUID().uuidString).mp4"))]

        await store.loadClipDetails(for: store.items[0].id)

        XCTAssertTrue(store.items[0].hasLoadedDetails)
        XCTAssertNil(store.items[0].thumbnail)
        XCTAssertNil(store.items[0].recordingDate)
    }

    @MainActor
    private func makeStore() -> BatchStore {
        let store = BatchStore()
        store.items = ["first.mp4", "middle.mp4", "last.mp4"].map {
            BatchItem(url: URL(fileURLWithPath: "/" + $0))
        }
        store.selectedItemID = store.items.first?.id
        return store
    }
}
