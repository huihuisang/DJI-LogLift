import AppKit
import SwiftUI
import XCTest

final class CameraGalleryFocusTests: XCTestCase {
    @MainActor
    func testSearchWaitsForExplicitFocus() throws {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1100, height: 760),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: GalleryFocusFixture())
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        XCTAssertTrue(window.firstResponder is GalleryInitialFocus.FocusView)
        let search = try XCTUnwrap(findSearch(in: host))
        XCTAssertNil(search.currentEditor())

        window.selectNextKeyView(nil)
        XCTAssertNotNil(search.currentEditor(), "Tab must still reach the search field")

        window.makeFirstResponder(window.initialFirstResponder)
        XCTAssertTrue(window.makeFirstResponder(search))
        let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
        editor.insertText("Osmo", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(search.stringValue, "Osmo")
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertNotNil(search.currentEditor(), "View updates must preserve user focus")
    }

    @MainActor
    private func findSearch(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { self.findSearch(in: $0) }.first
    }
}

private struct GalleryFocusFixture: View {
    @Namespace private var namespace
    private let store = BatchStore()
    private let artwork = ProductArtworkLibrary()
    private let order = CameraOrderStore()

    var body: some View {
        CameraGallery(store: store, artwork: artwork, namespace: namespace,
                      isVisible: true, choose: { _ in })
            .environment(order)
            .environment(\.studioReduceMotionPreview, true)
    }
}
