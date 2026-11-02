import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// This type is compiled into the build tool and test bundle, never the application.
enum ProductArtworkProcessor {
    static let processingVersion = 1

    static func prepare(sourceRoot: URL, outputRoot: URL) throws {
        guard sourceRoot.resolvingSymlinksInPath().standardizedFileURL != outputRoot.resolvingSymlinksInPath().standardizedFileURL else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let manifestData = try Data(contentsOf: sourceRoot.appendingPathComponent("manifest.json"))
        guard var manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let products = manifest["products"] as? [[String: Any]], !products.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var identifiers = Set<String>()
        var inputs = [(record: [String: Any], identifier: String, data: Data)]()
        for product in products {
            guard let identifier = product["id"] as? String,
                  isFileName(identifier), identifiers.insert(identifier).inserted,
                  let file = product["file"] as? String, isFileName(file),
                  let hash = product["sha256"] as? String,
                  product["hasAlpha"] is Bool,
                  product["displayBackground"] == nil || product["displayBackground"] as? String == "white" else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let data = try Data(contentsOf: sourceRoot.appendingPathComponent(file))
            guard checksum(data) == hash else { throw CocoaError(.fileReadCorruptFile) }
            inputs.append((product, identifier, data))
        }
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        var prepared = [[String: Any]]()
        for input in inputs {
            var product = input.record
            guard let source = CGImageSourceCreateWithData(input.data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 960,
                  ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
            let displayImage = product["displayBackground"] as? String == "white"
                ? removeEdgeConnectedWhiteBackground(thumbnail) : thumbnail
            let image = product["hasAlpha"] as? Bool == true || product["displayBackground"] != nil
                ? trimTransparentPadding(displayImage) : displayImage
            let png = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
            let file = input.identifier + ".png"
            try (png as Data).write(to: outputRoot.appendingPathComponent(file), options: .atomic)
            product["display"] = ["file": file, "sha256": checksum(png as Data),
                                  "width": image.width, "height": image.height]
            prepared.append(product)
        }
        manifest["products"] = prepared
        manifest["processingVersion"] = processingVersion
        manifest["sourceManifestSHA256"] = checksum(manifestData)
        let result = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try result.write(to: outputRoot.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private static func isFileName(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\")
    }

    private static func checksum(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func removeEdgeConnectedWhiteBackground(_ image: CGImage) -> CGImage {
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

    private static func trimTransparentPadding(_ image: CGImage) -> CGImage {
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
