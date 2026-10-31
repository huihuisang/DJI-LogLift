@preconcurrency import AVFoundation
import Foundation
import XCTest

final class ClipMetadataTests: XCTestCase, @unchecked Sendable {
    func testRecordingDateUsesCameraMetadataBeforeContainerDate() async throws {
        guard #available(macOS 15.0, *) else { throw XCTSkip("Native metadata fixture export requires macOS 15.") }
        let source = AVURLAsset(url: try fixture("synthetic-created.mp4"))
        let exporter = try XCTUnwrap(AVAssetExportSession(asset: source, presetName: AVAssetExportPresetPassthrough))
        let metadata = AVMutableMetadataItem()
        metadata.identifier = .quickTimeMetadataCreationDate
        metadata.value = "2026-10-30T12:13:50+08:00" as NSString
        metadata.dataType = kCMMetadataBaseDataType_UTF8 as String
        exporter.metadata = [metadata]
        let output = try fixture("native-recorded-\(UUID().uuidString).mov")
        try await exporter.export(to: output, as: .mov)

        let date = await ClipMetadata.recordingDate(source: output)
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-30T04:13:50Z"))
        XCTAssertEqual(date, expected)
    }

    func testRecordingDateFallsBackToEmbeddedContainerDate() async throws {
        let date = await ClipMetadata.recordingDate(source: try fixture("synthetic-created.mp4"))
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-29T02:30:00Z"))
        XCTAssertEqual(date, expected)
    }

    func testMissingMetadataDoesNotUseFilenameOrFilesystemDates() async throws {
        let date = await ClipMetadata.recordingDate(source: try fixture("DJI_20261030121350_0207_D.MP4"))
        XCTAssertNil(date)
    }

    func testMissingFileHasNoRecordingDate() async throws {
        let date = await ClipMetadata.recordingDate(source: try fixture("missing.mp4"))
        XCTAssertNil(date)
    }

    private func fixture(_ name: String) throws -> URL {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"])
        return URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(name)
    }
}
