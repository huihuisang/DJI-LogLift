import AppKit
import XCTest

final class FinderMenuIconTests: XCTestCase {
    func testMenuIconPreservesAppArtworkColors() throws {
        let image = try XCTUnwrap(FinderMenuIcon.applicationIcon(in: Bundle(for: Self.self)))
        XCTAssertFalse(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 16, height: 16))
        let data = try NSKeyedArchiver.archivedData(withRootObject: image, requiringSecureCoding: true)
        let restored = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: NSImage.self, from: data))
        XCTAssertFalse(restored.isTemplate)
        let cgImage = try XCTUnwrap(restored.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        for (x, y) in [(0, 0), (bitmap.pixelsWide - 1, 0),
                       (0, bitmap.pixelsHigh - 1), (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)] {
            XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0,
                           "Menu artwork must not contain an opaque background tile.")
        }
        var coloredPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.alphaComponent > 0.5,
                   max(color.redComponent, color.greenComponent, color.blueComponent)
                    - min(color.redComponent, color.greenComponent, color.blueComponent) > 0.12 {
                    coloredPixels += 1
                }
            }
        }
        XCTAssertGreaterThan(coloredPixels, 10)
    }

    func testMissingArtworkDoesNotUseAnUnrelatedIcon() {
        XCTAssertNil(FinderMenuIcon.applicationIcon(in: Bundle(for: NSImage.self)))
    }
}
