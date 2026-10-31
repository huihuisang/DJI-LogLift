import AppKit
import CryptoKit
import ImageIO
import LogBatchCore
import UniformTypeIdentifiers
import XCTest

final class ProductArtworkTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testEveryBundledCameraHasDecodableArtwork() async throws {
        let root = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("LogLift for DJI.app/Contents/Resources/ProductImages")
        let library = ProductArtworkLibrary()
        await library.prepare(resourceRoot: root)
        XCTAssertTrue(library.isReady, library.error ?? "")
        XCTAssertEqual(library.images.count, 36)
        let products = try LUTCatalog.load().products
        XCTAssertEqual(Set(library.images.keys), Set(products.map(\.id)))
        XCTAssertTrue(library.images.values.allSatisfy { $0.isValid })
        XCTAssertEqual(library.records["inspire-1-pro-and-raw"]?.representation, "official-family")
    }

    @MainActor
    func testPinnedWhiteBackgroundCamerasHaveTransparentDisplayCorners() async throws {
        let root = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("LogLift for DJI.app/Contents/Resources/ProductImages")
        let library = ProductArtworkLibrary()
        await library.prepare(resourceRoot: root)
        XCTAssertTrue(library.isReady)
        let identifiers = ["zenmuse-x5", "zenmuse-x5r"]
        XCTAssertEqual(Set(library.records.values.filter { $0.displayBackground == .white }.map(\.id)), Set(identifiers))
        let output = try fixtureRoot()
        for identifier in identifiers {
            let image = try XCTUnwrap(library.images[identifier])
            XCTAssertLessThan(image.size.width, 540)
            XCTAssertLessThan(image.size.height, 540)
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
            for x in [0, bitmap.pixelsWide - 1] {
                for y in [0, bitmap.pixelsHigh - 1] {
                    XCTAssertEqual(bitmap.colorAt(x: x, y: y)?.alphaComponent, 0, identifier)
                }
            }
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent(identifier + ".png"))
        }
    }

    @MainActor
    func testTransparentPaddingIsRemovedOnlyInTheDisplayImage() async throws {
        let root = try fixtureRoot()
        let bytes = try writeFixture(root)
        try writeManifest(root, hash: checksum(bytes))
        let library = ProductArtworkLibrary()
        await library.prepare(resourceRoot: root)
        XCTAssertTrue(library.isReady)
        let image = try XCTUnwrap(library.images["fixture"])
        // NSImage can synthesize retina representations; check the logical content bounds.
        XCTAssertEqual(image.size.width, 3)
        XCTAssertEqual(image.size.height, 4)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("fixture.png")), bytes)
    }

    @MainActor
    func testWhiteBackgroundRemovalPreservesEnclosedHighlightsAndSourceBytes() async throws {
        let root = try fixtureRoot()
        let bytes = try writeWhiteBackgroundFixture(root)
        try writeManifest(root, hash: checksum(bytes), hasAlpha: false, displayBackground: "white")
        let library = ProductArtworkLibrary()
        await library.prepare(resourceRoot: root)
        XCTAssertTrue(library.isReady)
        let image = try XCTUnwrap(library.images["fixture"])
        XCTAssertEqual(image.size, NSSize(width: 4, height: 4))
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        var transparentPixels = 0
        var whitePixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if color.alphaComponent == 0 { transparentPixels += 1 }
                if color.alphaComponent == 1 && color.redComponent > 0.95
                    && color.greenComponent > 0.95 && color.blueComponent > 0.95 { whitePixels += 1 }
            }
        }
        XCTAssertEqual(transparentPixels, 1)
        XCTAssertEqual(whitePixels, 1)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("fixture.png")), bytes)
    }

    @MainActor
    func testOpaqueArtworkWithoutAnExplicitBackgroundRuleStaysUnchanged() async throws {
        let root = try fixtureRoot()
        let bytes = try writeWhiteBackgroundFixture(root)
        try writeManifest(root, hash: checksum(bytes), hasAlpha: false)
        let library = ProductArtworkLibrary()
        await library.prepare(resourceRoot: root)
        XCTAssertTrue(library.isReady)
        XCTAssertEqual(library.images["fixture"]?.size, NSSize(width: 8, height: 6))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("fixture.png")), bytes)
    }

    @MainActor
    func testCorruptAndDuplicateManifestEntriesFailWithoutPartialArtwork() async throws {
        let root = try fixtureRoot()
        let bytes = try writeFixture(root)
        try writeManifest(root, hash: String(repeating: "0", count: 64))
        let corrupt = ProductArtworkLibrary()
        await corrupt.prepare(resourceRoot: root)
        XCTAssertFalse(corrupt.isReady)
        XCTAssertNotNil(corrupt.error)
        XCTAssertTrue(corrupt.images.isEmpty)
        try writeManifest(root, hash: checksum(bytes), duplicate: true)
        let duplicate = ProductArtworkLibrary()
        await duplicate.prepare(resourceRoot: root)
        XCTAssertFalse(duplicate.isReady)
        XCTAssertNotNil(duplicate.error)
        XCTAssertTrue(duplicate.images.isEmpty)
    }

    func testCameraCategoriesCoverEveryProductExactlyOnce() throws {
        let products = try LUTCatalog.load().products
        for product in products {
            XCTAssertTrue(CameraCategory.all.includes(product))
            XCTAssertEqual([CameraCategory.handheld, .aerial, .cinema].filter { $0.includes(product) }.count, 1)
        }
        XCTAssertTrue(CameraCategory.handheld.includes(try XCTUnwrap(products.first { $0.id == "nano" })))
        XCTAssertTrue(CameraCategory.aerial.includes(try XCTUnwrap(products.first { $0.id == "mini-4-pro" })))
        XCTAssertTrue(CameraCategory.cinema.includes(try XCTUnwrap(products.first { $0.id == "ronin-4d" })))
    }

    func testLUTMenuTitlesRemainDistinctForEveryCamera() throws {
        let catalog = try LUTCatalog.load()
        for product in catalog.products {
            let choices = catalog.luts(for: product.id)
            let titles = choices.map { LUTChoiceTitle.title(for: $0, among: choices) }
            XCTAssertEqual(Set(titles).count, choices.count, product.id)
        }
    }

    private func fixtureRoot() throws -> URL {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"])
        let root = URL(fileURLWithPath: path).appendingPathComponent("artwork-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func checksum(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func writeFixture(_ root: URL) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8,
                                             bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 2, y: 1, width: 3, height: 4))
        let image = try XCTUnwrap(context.makeImage())
        let url = root.appendingPathComponent("fixture.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return try Data(contentsOf: url)
    }

    private func writeWhiteBackgroundFixture(_ root: URL) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8,
                                             bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 2, y: 1, width: 4, height: 4))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 2, y: 1, width: 1, height: 1))
        context.fill(CGRect(x: 3, y: 2, width: 1, height: 1))
        let image = try XCTUnwrap(context.makeImage())
        let url = root.appendingPathComponent("fixture.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return try Data(contentsOf: url)
    }

    private func writeManifest(_ root: URL, hash: String, duplicate: Bool = false,
                               hasAlpha: Bool = true, displayBackground: String? = nil) throws {
        var item: [String: Any] = ["id": "fixture", "file": "fixture.png", "sha256": hash,
                                  "hasAlpha": hasAlpha, "representation": "product"]
        if let displayBackground { item["displayBackground"] = displayBackground }
        let data = try JSONSerialization.data(withJSONObject: ["products": duplicate ? [item, item] : [item]])
        try data.write(to: root.appendingPathComponent("manifest.json"))
    }
}
