import AppKit

enum FinderMenuIcon {
    static func applicationIcon(in bundle: Bundle) -> NSImage? {
        guard let url = bundle.url(forResource: "FinderAppIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        // Preserve the app artwork instead of depending on Finder's template tinting.
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = false
        return image
    }
}
