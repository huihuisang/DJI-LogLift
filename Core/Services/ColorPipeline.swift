import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation

public final class ColorPipeline {
    public let context: CIContext
    private let cube: CubeLUT

    public init(cube: CubeLUT) {
        self.cube = cube
        // The table consumes camera-encoded RGB and returns encoded Rec.709.
        // Automatic transfer-function conversion here would apply a second transform.
        context = CIContext(options: [
            .workingColorSpace: NSNull(), .outputColorSpace: NSNull(),
            .workingFormat: CIFormat.RGBAh,
        ])
    }

    public func apply(to image: CIImage) throws -> CIImage {
        let scale = SIMD3<Float>(repeating: 1) / (cube.domainMax - cube.domainMin)
        let offset = -cube.domainMin * scale
        let normalized = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(scale.x), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(scale.y), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(scale.z), w: 0),
            "inputBiasVector": CIVector(x: CGFloat(offset.x), y: CGFloat(offset.y), z: CGFloat(offset.z), w: 0),
        ])
        let filter = CIFilter.colorCube()
        filter.cubeDimension = Float(cube.dimension)
        filter.cubeData = cube.rgbaData
        filter.inputImage = normalized
        guard let result = filter.outputImage else { throw LogBatchError.processingFailed }
        return result
    }

    public static func image(from buffer: CVPixelBuffer) -> CIImage {
        CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
    }

    public static var readerSettings: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange]
    }
}
