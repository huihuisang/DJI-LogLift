@preconcurrency import AVFoundation
import CoreImage
import Foundation
import VideoToolbox

public enum VideoExporter {
    public static func export(
        source: URL, destination: URL, cube: CubeLUT,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw LogBatchError.outputExists }
        let media = try await VideoSource.load(source)
        let job = ExportJob(asset: media.asset, video: media.video, audio: media.audio,
                            audioFormat: media.audioFormat, size: media.size,
                            transform: media.transform, frameRate: media.frameRate, duration: media.duration,
                            destination: destination, cube: cube, progress: progress)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { try job.run(); continuation.resume() }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: {
            job.cancel()
        }
    }
}

// AVFoundation objects stay on one worker. Only cancellation crosses that boundary.
private final class ExportJob: @unchecked Sendable {
    let asset: AVAsset
    let video: AVAssetTrack
    let audio: AVAssetTrack?
    let audioFormat: CMFormatDescription?
    let size: CGSize
    let transform: CGAffineTransform
    let frameRate: Float
    let duration: CMTime
    let destination: URL
    let cube: CubeLUT
    let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var cancelled = false

    init(asset: AVAsset, video: AVAssetTrack, audio: AVAssetTrack?, audioFormat: CMFormatDescription?, size: CGSize,
         transform: CGAffineTransform, frameRate: Float, duration: CMTime,
         destination: URL, cube: CubeLUT, progress: @escaping @Sendable (Double) -> Void) {
        self.asset = asset; self.video = video; self.audio = audio; self.size = size
        self.audioFormat = audioFormat
        self.transform = transform; self.frameRate = frameRate; self.duration = duration
        self.destination = destination; self.cube = cube; self.progress = progress
    }

    func cancel() { lock.withLock { cancelled = true } }
    private var isCancelled: Bool { lock.withLock { cancelled } }

    func run() throws {
        let partial = destination.deletingLastPathComponent()
            .appendingPathComponent(".logbatch-\(UUID().uuidString).mp4")
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: partial, fileType: .mp4)
        var committed = false
        defer {
            if !committed {
                reader.cancelReading()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: partial)
            }
        }
        let videoOutput = AVAssetReaderTrackOutput(track: video, outputSettings: ColorPipeline.readerSettings)
        videoOutput.alwaysCopiesSampleData = false
        let rate = max(1, frameRate)
        let bitrate = Int(min(150_000_000, max(5_000_000, size.width * size.height * Double(rate) * 0.18)))
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel,
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: rate,
            ],
        ]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else { throw LogBatchError.unsupportedMedia }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.transform = transform
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ])
        guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else { throw LogBatchError.unsupportedMedia }
        reader.add(videoOutput)
        writer.add(videoInput)
        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audio {
            // Passthrough keeps the original compressed audio and timestamps.
            let output = AVAssetReaderTrackOutput(track: audio, outputSettings: nil)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormat)
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(output), writer.canAdd(input) else { throw LogBatchError.unsupportedMedia }
            reader.add(output); writer.add(input)
            audioOutput = output; audioInput = input
        }
        guard writer.startWriting(), reader.startReading() else {
            throw writer.error ?? reader.error ?? LogBatchError.processingFailed
        }
        writer.startSession(atSourceTime: .zero)
        let pipeline = ColorPipeline(cube: cube)
        var videoDone = false
        var audioDone = audioInput == nil
        var lastProgress = -1.0
        while !videoDone || !audioDone {
            if isCancelled { throw CancellationError() }
            guard writer.status == .writing, reader.status != .failed else {
                throw writer.error ?? reader.error ?? LogBatchError.processingFailed
            }
            var advanced = false
            if !videoDone && videoInput.isReadyForMoreMediaData {
                try autoreleasepool {
                    if let sample = videoOutput.copyNextSampleBuffer() {
                        guard let source = CMSampleBufferGetImageBuffer(sample), let pool = adaptor.pixelBufferPool else {
                            throw LogBatchError.processingFailed
                        }
                        var target: CVPixelBuffer?
                        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &target) == kCVReturnSuccess,
                              let target else { throw LogBatchError.processingFailed }
                        Self.tagRec709(target)
                        let result = try pipeline.apply(to: ColorPipeline.image(from: source))
                        pipeline.context.render(result, to: target, bounds: result.extent, colorSpace: nil)
                        let time = CMSampleBufferGetPresentationTimeStamp(sample)
                        guard adaptor.append(target, withPresentationTime: time) else {
                            throw writer.error ?? LogBatchError.processingFailed
                        }
                        let fraction = min(0.99, max(0, time.seconds / duration.seconds))
                        if fraction - lastProgress >= 0.01 { lastProgress = fraction; progress(fraction) }
                    } else {
                        videoDone = true
                        videoInput.markAsFinished()
                    }
                }
                advanced = true
            }
            if !audioDone, let audioInput, let audioOutput, audioInput.isReadyForMoreMediaData {
                if let sample = audioOutput.copyNextSampleBuffer() {
                    guard audioInput.append(sample) else { throw writer.error ?? LogBatchError.processingFailed }
                } else {
                    audioDone = true
                    audioInput.markAsFinished()
                }
                advanced = true
            }
            if !advanced { Thread.sleep(forTimeInterval: 0.002) }
        }
        guard reader.status == .completed else { throw reader.error ?? LogBatchError.processingFailed }
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        while finished.wait(timeout: .now() + 0.1) == .timedOut {
            if isCancelled { throw CancellationError() }
        }
        if isCancelled { throw CancellationError() }
        guard writer.status == .completed else { throw writer.error ?? LogBatchError.processingFailed }
        // moveItem fails on collisions, including files created while encoding.
        try FileManager.default.moveItem(at: partial, to: destination)
        committed = true
        progress(1)
    }

    private static func tagRec709(_ buffer: CVPixelBuffer) {
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey,
                              kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey,
                              kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey,
                              kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    }
}

