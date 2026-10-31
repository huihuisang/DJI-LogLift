@preconcurrency import AVFoundation
import CoreImage
import LogBatchCore
import XCTest

final class LogBatchCoreTests: XCTestCase, @unchecked Sendable {
    private var identityText: String {
        "LUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n"
    }

    func testRejectsTruncatedExtraAndNonFiniteSamples() throws {
        for text in [identityText.replacingOccurrences(of: "1 1 1\n", with: ""),
                     identityText + "0 0 0\n", identityText.replacingOccurrences(of: "1 1 1", with: "nan 1 1"),
                     "LUT_3D_SIZE 1\n0 0 0", "LUT_3D_SIZE 129\n", "0 0 0\n" + identityText] {
            XCTAssertThrowsError(try CubeLUT(data: Data(text.utf8)))
        }
    }

    func testRejectsShaperRatherThanSilentlyIgnoringIt() {
        XCTAssertThrowsError(try CubeLUT(data: Data("LUT_1D_SIZE 2\n0 0 0\n1 1 1\n".utf8))) {
            XCTAssertEqual($0 as? LogBatchError, .unsupportedCube)
        }
    }

    func testIdentityAndDomainMappingDoNotApplyAnExtraGamma() throws {
        let cube = try CubeLUT(data: Data(identityText.utf8))
        let pipeline = ColorPipeline(cube: cube)
        let pixel: [Float] = [0.18, 0.5, 0.75, 1]
        let bitmap = pixel.withUnsafeBytes { Data($0) }
        let image = CIImage(bitmapData: bitmap, bytesPerRow: 16, size: CGSize(width: 1, height: 1),
                            format: .RGBAf, colorSpace: nil)
        var result = [Float](repeating: 0, count: 4)
        pipeline.context.render(try pipeline.apply(to: image), toBitmap: &result, rowBytes: 16,
                                bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        for (actual, expected) in zip(result, pixel) { XCTAssertEqual(actual, expected, accuracy: 0.002) }
        let domainCube = try CubeLUT(data: Data(("DOMAIN_MIN -1 -1 -1\nDOMAIN_MAX 1 1 1\n" + identityText).utf8))
        let mapped = ColorPipeline(cube: domainCube)
        mapped.context.render(try mapped.apply(to: image), toBitmap: &result, rowBytes: 16,
                              bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        for (actual, expected) in zip(result.prefix(3), pixel.prefix(3)) {
            XCTAssertEqual(actual, (expected + 1) / 2, accuracy: 0.002)
        }
    }

    func testAllBundledCubesResolveAndMatchTheirChecksums() throws {
        let catalog = try LUTCatalog.load()
        XCTAssertEqual(catalog.packages.count, 44)
        XCTAssertEqual(catalog.luts.count, 64)
        XCTAssertEqual(Set(catalog.luts.map(\.id)).count, catalog.luts.count)
        for lut in catalog.luts {
            if lut.shaperDimension != nil {
                XCTAssertThrowsError(try catalog.loadCube(lut)) { XCTAssertEqual($0 as? LogBatchError, .unsupportedCube) }
            } else {
                let cube = try catalog.loadCube(lut)
                XCTAssertEqual(cube.dimension, lut.dimension, lut.id)
            }
        }
        let nano = try XCTUnwrap(catalog.luts(for: "nano").first)
        XCTAssertEqual(nano.inputProfile, "dlogM")
        XCTAssertTrue(nano.canConvertToRec709)
        XCTAssertTrue(catalog.luts.filter { $0.kind == "creative" }.allSatisfy { !$0.canConvertToRec709 })
        XCTAssertTrue(catalog.luts.filter { $0.outputProfile == "rec2020HLG" }.allSatisfy { !$0.canConvertToRec709 })
        XCTAssertEqual(catalog.luts(for: "mini-4-pro").count, 1)
    }

    private func fixture(_ name: String) throws -> URL {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"])
        let root = URL(fileURLWithPath: path, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("synthetic.mp4").path))
        return root.appendingPathComponent(name)
    }

    func testTenBitExportPreservesAudioDurationAndRotation() async throws {
        let source = try fixture("synthetic-rotated.mp4")
        let output = try fixture("identity-rec709.mp4")
        let cube = try CubeLUT(data: Data(identityText.utf8))
        try await VideoExporter.export(source: source, destination: output, cube: cube)
        let inputAsset = AVURLAsset(url: source)
        let outputAsset = AVURLAsset(url: output)
        let inputTracks = try await inputAsset.loadTracks(withMediaType: .video)
        let outputTracks = try await outputAsset.loadTracks(withMediaType: .video)
        let inputVideo = try XCTUnwrap(inputTracks.first)
        let outputVideo = try XCTUnwrap(outputTracks.first)
        let inputTransform = try await inputVideo.load(.preferredTransform)
        let outputTransform = try await outputVideo.load(.preferredTransform)
        XCTAssertEqual(inputTransform, outputTransform)
        let inputSize = try await inputVideo.load(.naturalSize)
        let outputSize = try await outputVideo.load(.naturalSize)
        XCTAssertEqual(inputSize, outputSize)
        let duration = try await outputAsset.load(.duration)
        let sourceDuration = try await inputAsset.load(.duration)
        XCTAssertEqual(duration.seconds, sourceDuration.seconds, accuracy: 0.05)
        let audio = try await outputAsset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 1)
        let formats = try await outputVideo.load(.formatDescriptions)
        let format = try XCTUnwrap(formats.first)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format), kCMVideoCodecType_HEVC)
        let transfer = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
        XCTAssertEqual(transfer, kCVImageBufferTransferFunction_ITU_R_709_2 as String)
        let preview = try await VideoPreview.load(source: source, cube: cube)
        XCTAssertEqual(preview.original.width, 180)
        XCTAssertEqual(preview.original.height, 320)
        let reference = try await PreviewOrientationTests.systemFrame(source)
        let exported = try await PreviewOrientationTests.systemFrame(output)
        XCTAssertLessThan(PreviewOrientationTests.pixelError(exported, reference), 8)
    }

    func testNanoOfficialLUTExportsSyntheticVideo() async throws {
        let catalog = try LUTCatalog.load()
        let nano = try XCTUnwrap(catalog.luts(for: "nano").first)
        try await VideoExporter.export(source: fixture("synthetic.mp4"), destination: fixture("nano-rec709.mp4"),
                                       cube: catalog.loadCube(nano))
    }

    func testThumbnailsFitTheirBoundsAndRespectRotation() async throws {
        let landscape = try await VideoPreview.thumbnail(source: fixture("synthetic.mp4"))
        XCTAssertEqual(landscape.width, 192)
        XCTAssertEqual(landscape.height, 108)

        let portrait = try await VideoPreview.thumbnail(source: fixture("synthetic-rotated.mp4"))
        XCTAssertEqual(Double(portrait.width), 120 * 180 / 320, accuracy: 1)
        XCTAssertEqual(portrait.height, 120)
    }

    func testThumbnailRejectsMissingMedia() async throws {
        do {
            _ = try await VideoPreview.thumbnail(source: fixture("missing.mp4"))
            XCTFail("Missing media must not produce a thumbnail")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: try fixture("missing.mp4").path))
        }
    }

    func testRejectsHLGAndKeepsExistingDestinationUnchanged() async throws {
        let cube = try CubeLUT(data: Data(identityText.utf8))
        let destination = try fixture("existing.mp4")
        let sentinel = Data("Keep this user file".utf8)
        try sentinel.write(to: destination)
        do {
            try await VideoExporter.export(source: fixture("synthetic.mp4"), destination: destination, cube: cube)
            XCTFail("Existing destination must be rejected")
        } catch { XCTAssertEqual(error as? LogBatchError, .outputExists) }
        XCTAssertEqual(try Data(contentsOf: destination), sentinel)
        let rejected = try fixture("rejected-hlg.mp4")
        do {
            try await VideoExporter.export(source: fixture("synthetic-hlg.mp4"), destination: rejected, cube: cube)
            XCTFail("HLG must not receive a Log conversion")
        } catch { XCTAssertEqual(error as? LogBatchError, .unsupportedMedia) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: rejected.path))
        do {
            _ = try await VideoPreview.load(source: fixture("synthetic-hlg.mp4"), cube: cube)
            XCTFail("Preview must reject HLG too")
        } catch { XCTAssertEqual(error as? LogBatchError, .unsupportedMedia) }
        do {
            _ = try await VideoPreview.load(source: fixture("synthetic-multitrack.mp4"), cube: cube)
            XCTFail("Preview must reject multiple video tracks")
        } catch { XCTAssertEqual(error as? LogBatchError, .unsupportedMedia) }
        do {
            try await VideoExporter.export(source: fixture("synthetic-multitrack.mp4"),
                                           destination: fixture("rejected-multitrack.mp4"), cube: cube)
            XCTFail("Export must reject multiple video tracks")
        } catch { XCTAssertEqual(error as? LogBatchError, .unsupportedMedia) }
    }

    func testCancellationDoesNotPublishAPartialFile() async throws {
        let source = try fixture("synthetic.mp4")
        let output = try fixture("cancelled.mp4")
        let cube = try CubeLUT(data: Data(identityText.utf8))
        let task = Task { try await VideoExporter.export(source: source, destination: output, cube: cube) }
        task.cancel()
        do { try await task.value; XCTFail("Cancelled export must fail") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let remaining = try FileManager.default.contentsOfDirectory(atPath: output.deletingLastPathComponent().path)
        XCTAssertFalse(remaining.contains { $0.hasPrefix(".logbatch-") })
    }

    func testCancellationDuringEncodingRemovesPartialFile() async throws {
        let source = try fixture("synthetic.mp4")
        let output = try fixture("cancelled-mid-export.mp4")
        let cube = try CubeLUT(data: Data(identityText.utf8))
        let cancellation = CancellationBox()
        let task = Task {
            try await VideoExporter.export(source: source, destination: output, cube: cube) { _ in cancellation.cancel() }
        }
        cancellation.set(task)
        do { try await task.value; XCTFail("Cancelled export must fail") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let remaining = try FileManager.default.contentsOfDirectory(atPath: output.deletingLastPathComponent().path)
        XCTAssertFalse(remaining.contains { $0.hasPrefix(".logbatch-") })
    }

    func testDestinationCreatedDuringEncodingIsPreserved() async throws {
        let source = try fixture("synthetic.mp4")
        let output = try fixture("collision-during-export.mp4")
        let cube = try CubeLUT(data: Data(identityText.utf8))
        let sentinel = Data("A file created by another process".utf8)
        do {
            try await VideoExporter.export(source: source, destination: output, cube: cube) { _ in
                if !FileManager.default.fileExists(atPath: output.path) { try? sentinel.write(to: output) }
            }
            XCTFail("Export must not overwrite the concurrent destination")
        } catch {
            XCTAssertEqual(try Data(contentsOf: output), sentinel)
        }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: output.deletingLastPathComponent().path)
        XCTAssertFalse(remaining.contains { $0.hasPrefix(".logbatch-") })
    }
}

private final class CancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Error>?
    func set(_ task: Task<Void, Error>) { lock.withLock { self.task = task } }
    func cancel() { lock.withLock { task?.cancel() } }
}
