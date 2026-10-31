@preconcurrency import AVFoundation
import Foundation

struct VideoSource {
    let asset: AVURLAsset
    let video: AVAssetTrack
    let audio: AVAssetTrack?
    let audioFormat: CMFormatDescription?
    let size: CGSize
    let transform: CGAffineTransform
    let frameRate: Float
    let duration: CMTime

    static func load(_ url: URL) async throws -> Self {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard videoTracks.count == 1, audioTracks.count <= 1, let video = videoTracks.first else {
            throw LogBatchError.unsupportedMedia
        }
        let size = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let frameRate = try await video.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        let formats = try await video.load(.formatDescriptions)
        let audioFormat = try await audioTracks.first?.load(.formatDescriptions).first
        guard duration.seconds.isFinite, duration.seconds > 0,
              size.width > 0, size.height > 0,
              Int(size.width) % 2 == 0, Int(size.height) % 2 == 0 else { throw LogBatchError.unsupportedMedia }
        for format in formats {
            let transfer = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_TransferFunction)
            let value = transfer as? String
            if value == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String
                || value == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String {
                throw LogBatchError.unsupportedMedia
            }
        }
        return Self(asset: asset, video: video, audio: audioTracks.first, audioFormat: audioFormat,
                    size: size, transform: transform, frameRate: frameRate, duration: duration)
    }
}

