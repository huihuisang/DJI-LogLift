import AppKit
import XCTest

final class FinderImportRequestTests: XCTestCase {
    @MainActor
    func testMultiSelectionUsesOneShortRequestAndCanOnlyBeConsumedOnce() throws {
        let files = [URL(fileURLWithPath: "/Movies/第一 段.mp4"), URL(fileURLWithPath: "/Movies/second.MOV")]
        let generalChangeCount = NSPasteboard.general.changeCount
        let url = try FinderImportRequest.publish(files)

        XCTAssertLessThan(url.absoluteString.count, 100)
        XCTAssertFalse(url.absoluteString.contains("Movies"))
        XCTAssertEqual(try FinderImportRequest.consume(url).files, files)
        XCTAssertThrowsError(try FinderImportRequest.consume(url))
        XCTAssertEqual(NSPasteboard.general.changeCount, generalChangeCount)
    }

    @MainActor
    func testInvalidInputsAndWakeupURLsAreRejected() {
        for files in [[URL](), [URL(string: "https://example.com/video.mp4")!],
                      [URL(fileURLWithPath: "/Movies/notes.txt")],
                      Array(repeating: URL(fileURLWithPath: "/Movies/video.mp4"), count: 10_001)] {
            XCTAssertThrowsError(try FinderImportRequest.publish(files))
        }
        for text in ["https://import?request=bad", "loglift://import?request=bad",
                     "loglift://import?request=\(UUID())&request=\(UUID())", "loglift://import/path?request=\(UUID())",
                     "loglift://user@import?request=\(UUID())", "loglift://import:80?request=\(UUID())"] {
            XCTAssertThrowsError(try FinderImportRequest.consume(URL(string: text)!))
        }
    }

    @MainActor
    func testInvalidVersionExpiredRequestsAndOversizedPayloadsAreRejected() throws {
        let files = [URL(fileURLWithPath: "/Movies/video.mp4")]
        for request in [FinderImportRequest(version: 2, files: files),
                        FinderImportRequest(createdAt: Date().addingTimeInterval(-601), files: files),
                        FinderImportRequest(createdAt: Date().addingTimeInterval(61), files: files)] {
            let url = writePayload(try JSONEncoder().encode(request))
            XCTAssertThrowsError(try FinderImportRequest.consume(url))
        }
        let oversized = writePayload(Data(repeating: 0, count: FinderImportRequest.maximumBytes + 1))
        XCTAssertThrowsError(try FinderImportRequest.consume(oversized))
    }

    @MainActor
    private func writePayload(_ data: Data) -> URL {
        let token = UUID().uuidString
        let board = NSPasteboard(name: .init("dev.logbatch.import." + token))
        let type = NSPasteboard.PasteboardType("dev.logbatch.video-import")
        board.declareTypes([type], owner: nil)
        XCTAssertTrue(board.setData(data, forType: type))
        return URL(string: "loglift://import?request=" + token)!
    }
}
