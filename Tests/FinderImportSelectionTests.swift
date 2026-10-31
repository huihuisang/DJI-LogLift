import Foundation
import XCTest

final class FinderImportSelectionTests: XCTestCase {
    func testSelectionKeepsAllSupportedFilesAndRemovesDuplicates() throws {
        let root = try makeDirectory()
        let files = try ["第一 段.MOV", "second.mp4", "third.m4v", "notes.txt"].map { name in
            let url = root.appendingPathComponent(name)
            try Data("Original test data".utf8).write(to: url)
            return url
        }
        let directory = root.appendingPathComponent("folder.mp4", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let link = root.appendingPathComponent("link.mov")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: files[0])
        let missing = root.appendingPathComponent("missing.mp4")

        XCTAssertEqual(VideoFiles.selection(from: files + [files[0], directory, link, missing,
                                                           URL(string: "https://example.com/video.mp4")!]),
                       Array(files.prefix(3)))
        XCTAssertTrue(VideoFiles.selection(from: [files[3], directory, missing]).isEmpty)
        XCTAssertTrue(VideoFiles.selection(from: []).isEmpty)
    }

    func testContainingApplicationIsDerivedFromTheEmbeddedExtension() {
        let app = URL(fileURLWithPath: "/Applications/LogLift for DJI.app", isDirectory: true)
        let embedded = app.appendingPathComponent("Contents/PlugIns/LogLiftFinderExtension.appex", isDirectory: true)
        XCTAssertEqual(ContainingApplication.url(forExtensionAt: embedded), app)
        XCTAssertNil(ContainingApplication.url(forExtensionAt: URL(fileURLWithPath: "/tmp/Finder.appex")))
        XCTAssertNil(ContainingApplication.url(forExtensionAt: app))
        XCTAssertNil(ContainingApplication.url(forExtensionAt: URL(string: "https://example.com/App.app/Contents/PlugIns/Finder.appex")!))
    }

    func testRequestValidationDoesNotRequireMetadataAccessBeforeAuthorization() {
        let missing = URL(fileURLWithPath: "/unapproved-\(UUID())/第一 段.mp4")
        XCTAssertEqual(VideoFiles.requestedSelection(from: [missing, missing]), [missing])
        XCTAssertTrue(VideoFiles.selection(from: [missing]).isEmpty)
    }

    private func makeDirectory() throws -> URL {
        let base = try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"])
        let root = URL(fileURLWithPath: base, isDirectory: true)
            .appendingPathComponent("finder-selection/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
