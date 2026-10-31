import CoreImage
import CoreVideo
import Foundation

// CIContext supports concurrent use. Each frame uses its own filter instances.
public final class VideoPreviewRenderer: @unchecked Sendable {
    private let pipeline: ColorPipeline
    private let transform: CGAffineTransform
    private let maximumDimension: CGFloat = 1280

    public init(cube: CubeLUT, transform: CGAffineTransform) {
        pipeline = ColorPipeline(cube: cube)
        let flipY = CGAffineTransform(scaleX: 1, y: -1)
        self.transform = flipY.concatenating(transform).concatenating(flipY)
    }

    public func render(_ buffer: CVPixelBuffer) throws -> PreviewImages {
        let input = ColorPipeline.image(from: buffer)
        return try PreviewImages(original: frame(input), converted: frame(pipeline.apply(to: input)))
    }

    private func frame(_ image: CIImage) throws -> CGImage {
        // Track display coordinates and Core Image have opposite Y axes.
        let rotated = image.transformed(by: transform)
        let origin = rotated.extent.origin
        let normalized = rotated.transformed(by: .init(translationX: -origin.x, y: -origin.y))
        let scale = min(1, maximumDimension / max(normalized.extent.width, normalized.extent.height))
        let scaled = normalized.transformed(by: .init(scaleX: scale, y: scale))
        guard let result = pipeline.context.createCGImage(scaled, from: scaled.extent, format: .RGBA8,
                                                         colorSpace: CGColorSpace(name: CGColorSpace.itur_709)) else {
            throw LogBatchError.processingFailed
        }
        return result
    }
}
