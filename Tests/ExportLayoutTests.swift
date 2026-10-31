import AppKit
import LogBatchCore
import SwiftUI
import XCTest

final class ExportLayoutTests: XCTestCase {
    @MainActor
    func testCompletedQueueUsesTheOriginalButtonWhenFeedbackIsIdle() throws {
        let store = makeStore()
        let size = NSSize(width: 336, height: 280)
        let empty = try render(ExportBar(store: store).padding(24).frame(width: 336, height: 280, alignment: .bottom),
                               size: size, name: "export-idle-empty")
        store.items = [BatchItem(url: URL(fileURLWithPath: "/completed.mp4"))]
        store.items[0].status = .completed
        let completed = try render(ExportBar(store: store).padding(24).frame(width: 336, height: 280, alignment: .bottom),
                                   size: size, name: "export-idle-completed")
        let scale = CGFloat(empty.pixelsWide) / size.width
        var differentPixels = 0
        for y in Int(200 * scale)..<Int(256 * scale) {
            for x in Int(24 * scale)..<Int(312 * scale) {
                if empty.colorAt(x: x, y: y) != completed.colorAt(x: x, y: y) { differentPixels += 1 }
            }
        }
        XCTAssertEqual(differentPixels, 0, "Completed clips must not leave the button in a permanent success state")
    }

    @MainActor
    func testCompletedQueuePillUsesGreenBackgroundAndWhiteText() throws {
        let store = makeStore()
        var completed = BatchItem(url: URL(fileURLWithPath: "/completed.mp4"))
        completed.status = .completed
        completed.hasLoadedDetails = true
        store.items = [completed]
        for scheme in [ColorScheme.dark, .light] {
            for selected in [false, true] {
                store.selectedItemID = selected ? completed.id : nil
                let bitmap = try render(QueuePane(store: store).padding(24),
                                        size: NSSize(width: 780, height: 220),
                                        name: "completed-pill-\(scheme)-\(selected)", scheme: scheme)
                var greenPoints = [CGPoint]()
                for y in 0..<bitmap.pixelsHigh {
                    for x in (bitmap.pixelsWide / 2)..<bitmap.pixelsWide {
                        if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                           color.greenComponent > 0.3 && color.greenComponent > color.redComponent * 1.7
                            && color.greenComponent > color.blueComponent * 1.2 {
                            greenPoints.append(CGPoint(x: x, y: y))
                        }
                    }
                }
                XCTAssertGreaterThan(greenPoints.count, 100)
                let minX = Int(try XCTUnwrap(greenPoints.map(\.x).min()))
                let maxX = Int(try XCTUnwrap(greenPoints.map(\.x).max()))
                let minY = Int(try XCTUnwrap(greenPoints.map(\.y).min()))
                let maxY = Int(try XCTUnwrap(greenPoints.map(\.y).max()))
                var whitePixels = 0
                for y in minY...maxY {
                    for x in minX...maxX {
                        if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                           color.redComponent > 0.9 && color.greenComponent > 0.9 && color.blueComponent > 0.9 {
                            whitePixels += 1
                        }
                    }
                }
                XCTAssertGreaterThan(whitePixels, 20)
            }
        }
    }

    @MainActor
    func testExportStatesAndLocalizedButtonLayout() throws {
        let store = makeStore()
        for state in ["empty", "ready", "no-folder", "processing", "failed", "completed"] {
            store.outputDirectory = state == "no-folder" ? nil : URL(fileURLWithPath: "/Movies/LogBatch")
            store.items = state == "empty" ? [] : (0..<3).map {
                BatchItem(url: URL(fileURLWithPath: "/fixture-\($0).mp4"))
            }
            store.isProcessing = state == "processing"
            if state == "completed" {
                for index in store.items.indices { store.items[index].status = .completed }
            } else if state == "failed" {
                store.items[0].status = .completed
                store.items[1].status = .failed
            }
            let view = ExportBar(store: store).padding(24)
                .frame(width: 336, height: 280, alignment: .bottom)
            let bitmap = try render(view, size: NSSize(width: 336, height: 280), name: "export-" + state)
            XCTAssertEqual(store.canStart, ["ready", "no-folder", "failed"].contains(state))
            if state != "processing" { try checkButton(in: bitmap, logicalSize: NSSize(width: 336, height: 280)) }
        }

        store.isProcessing = false
        store.items = [BatchItem(url: URL(fileURLWithPath: "/fixture.mp4"))]
        store.outputDirectory = URL(fileURLWithPath: "/Volumes/Footage/An extremely long export destination folder name")
        for locale in ["en", "zh-Hans", "ja", "ko"] {
            for scheme in [ColorScheme.dark, .light] {
                let view = ExportBar(store: store).padding(24)
                    .frame(width: 336, height: 280, alignment: .bottom)
                    .environment(\.locale, Locale(identifier: locale))
                let bitmap = try render(view, size: NSSize(width: 336, height: 280),
                                        name: "export-\(locale)-\(scheme)", scheme: scheme)
                try checkButton(in: bitmap, logicalSize: NSSize(width: 336, height: 280), checkCenter: true)
            }
        }
    }

    @MainActor
    func testWorkspaceKeepsExportVisibleAtMinimumAndDefaultSizes() async throws {
        let store = makeStore()
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"])
        let source = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("synthetic.mp4")
        store.items = [BatchItem(url: source)]
        store.selectedItemID = store.items[0].id
        store.playback.isMuted = true
        await store.loadPreview()
        defer { store.playback.stop() }
        let deadline = Date().addingTimeInterval(4)
        while !store.playback.isReady, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(store.playback.isReady)
        let product = try XCTUnwrap(store.catalog?.products.first { $0.id == "nano" })
        let artwork = ProductArtworkLibrary()
        let resources = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("LogLift for DJI.app/Contents/Resources/ProductImages")
        await artwork.prepare(resourceRoot: resources)
        for size in [NSSize(width: 1100, height: 760), NSSize(width: 1280, height: 900)] {
            let view = WorkspaceFixture(store: store, product: product, artwork: artwork)
            let bitmap = try render(view, size: size, name: "workspace-\(Int(size.width))")
            try checkButton(in: bitmap, logicalSize: size, checkCenter: true)
        }
    }

    private func checkButton(in bitmap: NSBitmapImageRep, logicalSize: NSSize, checkCenter: Bool = false) throws {
        let scale = CGFloat(bitmap.pixelsWide) / logicalSize.width
        var points = [CGPoint]()
        for y in (bitmap.pixelsHigh - Int(130 * scale))..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.3 && color.redComponent > color.greenComponent * 1.9 {
                    points.append(CGPoint(x: x, y: y))
                }
            }
        }
        let minX = try XCTUnwrap(points.map(\.x).min())
        let maxX = try XCTUnwrap(points.map(\.x).max())
        let minY = try XCTUnwrap(points.map(\.y).min())
        let maxY = try XCTUnwrap(points.map(\.y).max())
        XCTAssertEqual((maxX - minX + 1) / scale, 288, accuracy: 1)
        XCTAssertEqual((maxY - minY + 1) / scale, 56, accuracy: 1)
        XCTAssertGreaterThan(logicalSize.height - maxY / scale, 20)
        if checkCenter {
            var textX = [Int]()
            var iconPixels = 0
            for y in Int(minY)...Int(maxY) {
                for x in Int(minX + 16 * scale)...Int(minX + 42 * scale) {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                       color.redComponent > 0.9 && color.greenComponent > 0.9 && color.blueComponent > 0.9 {
                        iconPixels += 1
                    }
                }
                for x in Int(minX + 46 * scale)...Int(maxX - 46 * scale) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.redComponent > 0.9 && color.greenComponent > 0.9 && color.blueComponent > 0.9 { textX.append(x) }
                }
            }
            let textMin = try XCTUnwrap(textX.min())
            let textMax = try XCTUnwrap(textX.max())
            XCTAssertEqual(CGFloat(textMin + textMax) / 2 / scale, (minX + maxX) / 2 / scale, accuracy: 2)
            XCTAssertGreaterThan(iconPixels, 20)
        }
    }

    @MainActor
    private func makeStore() -> BatchStore {
        let store = BatchStore()
        store.outputDirectory = URL(fileURLWithPath: "/Movies/LogBatch")
        return store
    }

    @MainActor
    private func render<V: View>(_ content: V, size: NSSize, name: String, scheme: ColorScheme = .dark) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: content
            .environment(\.colorScheme, scheme)
            .environment(\.studioReduceMotionPreview, true)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let root = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"]))
            .appendingPathComponent("export-layout", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent(name + ".png"))
        window.close()
        return bitmap
    }
}

private struct WorkspaceFixture: View {
    let store: BatchStore
    let product: DJIProduct
    let artwork: ProductArtworkLibrary
    @Namespace private var namespace

    var body: some View {
        ConversionWorkspace(store: store, product: product, artwork: artwork, namespace: namespace,
                            isHeroSource: true, showGallery: {})
    }
}
