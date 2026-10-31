@preconcurrency import AVFoundation
import CoreImage
import Foundation

public struct PreviewImages: @unchecked Sendable {
    public let original: CGImage
    public let converted: CGImage
}

public enum VideoPreview {
    public static func thumbnail(source: URL) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 192, height: 120)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: .zero).image
    }

    public static func load(source: URL, cube: CubeLUT) async throws -> PreviewImages {
        let media = try await VideoSource.load(source)
        let reader = try AVAssetReader(asset: media.asset)
        defer { reader.cancelReading() }
        let output = AVAssetReaderTrackOutput(track: media.video, outputSettings: ColorPipeline.readerSettings)
        guard reader.canAdd(output) else { throw LogBatchError.unsupportedMedia }
        reader.add(output)
        guard reader.startReading(), let sample = output.copyNextSampleBuffer(),
              let buffer = CMSampleBufferGetImageBuffer(sample) else {
            throw reader.error ?? LogBatchError.processingFailed
        }
        return try VideoPreviewRenderer(cube: cube, transform: media.transform).render(buffer)
    }
}
