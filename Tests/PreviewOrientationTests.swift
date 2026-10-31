@preconcurrency import AVFoundation
import CoreGraphics
import LogBatchCore
import XCTest

final class PreviewOrientationTests: XCTestCase, @unchecked Sendable {
    func testPreviewPixelsMatchSystemOrientationForRotationsAndMirrors() async throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"])
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let cube = try CubeLUT(data: Data("LUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n".utf8))
        for rotation in [0, 90, 180, 270] {
            for mirrored in [false, true] {
                let name = "synthetic-orientation-\(rotation)-\(mirrored).mp4"
                let source = root.appendingPathComponent(name)
                let reference = try await Self.systemFrame(source)
                let images = try await VideoPreview.load(source: source, cube: cube)
                for image in [images.original, images.converted] {
                    XCTAssertEqual(image.width, reference.width, name)
                    XCTAssertEqual(image.height, reference.height, name)
                    XCTAssertLessThan(Self.pixelError(image, reference), 8, name)
                }
            }
        }
    }

    static func systemFrame(_ source: URL) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: .zero).image
    }

    static func pixelError(_ image: CGImage, _ reference: CGImage) -> Double {
        func pixels(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: 32 * 32 * 4)
            data.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: 32, height: 32, bitsPerComponent: 8,
                                        bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            }
            return data
        }
        let actual = pixels(image)
        let expected = pixels(reference)
        let sum = actual.indices.filter { $0 % 4 != 3 }.reduce(0.0) {
            $0 + abs(Double(actual[$1]) - Double(expected[$1]))
        }
        return sum / (32 * 32 * 3)
    }
}
