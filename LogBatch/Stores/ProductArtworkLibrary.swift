import AppKit
import CryptoKit
import ImageIO
import Observation

struct ProductArtwork: Decodable, Sendable {
    enum DisplayBackground: String, Decodable, Sendable {
        case white
    }

    let id: String
    let file: String
    let sha256: String
    let hasAlpha: Bool
    let representation: String?
    let displayBackground: DisplayBackground?
}

private struct ArtworkManifest: Decodable {
    let products: [ProductArtwork]
}

// CGImage values are immutable after decoding and are handed to the main actor once.
private struct DecodedArtwork: @unchecked Sendable {
    let images: [String: CGImage]
}

@MainActor @Observable
final class ProductArtworkLibrary {
    private(set) var images = [String: NSImage]()
    private(set) var records = [String: ProductArtwork]()
    private(set) var isReady = false
    private(set) var isPreparing = false
    private(set) var error: String?

    func prepare(resourceRoot: URL? = nil) async {
        guard !isReady && !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            guard let root = resourceRoot ?? Bundle.main.url(forResource: "ProductImages", withExtension: nil) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let manifest = try JSONDecoder().decode(ArtworkManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
            guard Set(manifest.products.map(\.id)).count == manifest.products.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            records = Dictionary(uniqueKeysWithValues: manifest.products.map { ($0.id, $0) })
            let products = manifest.products
            let decoded = try await Task.detached(priority: .userInitiated) {
                var images = [String: CGImage]()
                for product in products {
                    let url = root.appendingPathComponent(product.file)
                    let data = try Data(contentsOf: url)
                    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    guard hash == product.sha256,
                          let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 960,
                          ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
                    let displayImage = product.displayBackground == .white
                        ? Self.removeEdgeConnectedWhiteBackground(thumbnail) : thumbnail
                    images[product.id] = product.hasAlpha || product.displayBackground != nil
                        ? Self.trimTransparentPadding(displayImage) : displayImage
                }
                return DecodedArtwork(images: images)
            }.value
            images = decoded.images.mapValues { NSImage(cgImage: $0, size: .zero) }
            isReady = true
        } catch {
            self.error = String(localized: "Product images could not be loaded. Please rebuild the app.")
        }
    }

    private nonisolated static func removeEdgeConnectedWhiteBackground(_ image: CGImage) -> CGImage {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var queue = [Int]()
        queue.reserveCapacity(width * height)

        func clearIfWhite(_ index: Int) {
            let offset = index * 4
            guard pixels[offset + 3] > 0,
                  pixels[offset] >= 240, pixels[offset + 1] >= 240, pixels[offset + 2] >= 240 else { return }
            pixels[offset] = 0; pixels[offset + 1] = 0; pixels[offset + 2] = 0; pixels[offset + 3] = 0
            queue.append(index)
        }

        for x in 0..<width {
            clearIfWhite(x)
            clearIfWhite((height - 1) * width + x)
        }
        for y in 0..<height {
            clearIfWhite(y * width)
            clearIfWhite(y * width + width - 1)
        }
        // Only the edge-connected backdrop is removed; enclosed highlights remain opaque.
        var head = 0
        while head < queue.count {
            let index = queue[head]
            head += 1
            let x = index % width, y = index / width
            if x > 0 { clearIfWhite(index - 1) }
            if x + 1 < width { clearIfWhite(index + 1) }
            if y > 0 { clearIfWhite(index - width) }
            if y + 1 < height { clearIfWhite(index + width) }
        }
        return context.makeImage() ?? image
    }

    private nonisolated static func trimTransparentPadding(_ image: CGImage) -> CGImage {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var minX = width, minY = height, maxX = 0, maxY = 0
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 0 {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX, minY <= maxY else { return image }
        let bounds = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        return context.makeImage()?.cropping(to: bounds) ?? image
    }
}

