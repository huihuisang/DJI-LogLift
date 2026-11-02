import AppKit
import LogBatchCore
import SwiftUI
import XCTest

final class AjiguPromotionTests: XCTestCase {
    @MainActor
    func testMascotResourceKeepsItsTransparentBackground() throws {
        let image = try XCTUnwrap(Bundle(for: Self.self).image(forResource: "AjiguMascot"))
        XCTAssertFalse(image.isTemplate)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        for (x, y) in [(0, 0), (bitmap.pixelsWide - 1, 0),
                       (0, bitmap.pixelsHigh - 1), (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)] {
            XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0,
                           "The mascot must not contain an opaque background tile.")
        }
    }

    @MainActor
    func testGalleryRendersSupportedLanguagesAndAppearances() async throws {
        let store = BatchStore()
        let artwork = ProductArtworkLibrary()
        let resources = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("LogLift for DJI.app/Contents/Resources/PreparedProductImages")
        await artwork.prepare(resourceRoot: resources)
        XCTAssertFalse(artwork.records.isEmpty)

        for language in ["en", "zh-Hans", "ja", "ko"] {
            try renderGallery(store: store, artwork: artwork, language: language,
                              size: NSSize(width: 1100, height: 760), scheme: .light)
        }
        for scheme in [ColorScheme.light, .dark] {
            try renderGallery(store: store, artwork: artwork, language: "zh-Hans",
                              size: NSSize(width: 1280, height: 900), scheme: scheme)
        }
    }

    @MainActor
    private func renderGallery(store: BatchStore, artwork: ProductArtworkLibrary, language: String,
                               size: NSSize, scheme: ColorScheme) throws {
        let view = PromotionGalleryFixture(store: store, artwork: artwork)
            .environment(\.locale, Locale(identifier: language))
            .environment(\.colorScheme, scheme)
            .environment(\.studioReduceMotionPreview, true)
            .background(Color(nsColor: .windowBackgroundColor))
        let (window, host) = makeWindow(view, size: size, scheme: scheme)
        defer { window.close() }

        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"]))
            .appendingPathComponent("ajigu-promotion", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(language)-\(Int(size.width))-\(scheme == .dark ? "dark" : "light").png"
        try png.write(to: directory.appendingPathComponent(name))
    }

    @MainActor
    private func makeWindow<V: View>(_ content: V, size: NSSize, scheme: ColorScheme = .light)
        -> (NSWindow, NSHostingView<V>) {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: content)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        return (window, host)
    }
}

private struct PromotionGalleryFixture: View {
    let store: BatchStore
    let artwork: ProductArtworkLibrary
    @Namespace private var namespace
    @State private var order = CameraOrderStore()

    var body: some View {
        CameraGallery(store: store, artwork: artwork, namespace: namespace, isVisible: true, choose: { _ in })
            .environment(order)
    }
}
