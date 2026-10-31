import AppKit
import SwiftUI

struct GalleryInitialFocus: NSViewRepresentable {
    func makeNSView(context: Context) -> FocusView { FocusView() }

    func updateNSView(_ nsView: FocusView, context: Context) {}

    final class FocusView: NSView {
        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Keep automatic window focus out of the search field without adding a Tab stop.
            window?.initialFirstResponder = self
        }
    }
}
