import AppKit
import Observation

struct ProductArtwork: Decodable, Sendable {
    enum DisplayBackground: String, Decodable, Sendable {
        case white
    }

    struct Display: Decodable, Sendable {
        let file: String
        let sha256: String
        let width: Int
        let height: Int
    }

    let display: Display
    let id: String
    let file: String
    let sha256: String
    let hasAlpha: Bool
    let representation: String?
    let displayBackground: DisplayBackground?
}

private struct ArtworkManifest: Decodable {
    let processingVersion: Int
    let products: [ProductArtwork]
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
        error = nil
        defer { isPreparing = false }
        do {
            guard let root = resourceRoot ?? Bundle.main.url(forResource: "PreparedProductImages", withExtension: nil) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let manifest = try JSONDecoder().decode(ArtworkManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
            guard manifest.processingVersion == 1, !manifest.products.isEmpty,
                  Set(manifest.products.map(\.id)).count == manifest.products.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            var prepared = [String: NSImage]()
            for product in manifest.products {
                let display = product.display
                guard !product.id.contains("/"), !product.id.contains("\\"),
                      display.file == product.id + ".png",
                      (1...960).contains(display.width), (1...960).contains(display.height) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let url = root.appendingPathComponent(display.file)
                guard FileManager.default.isReadableFile(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
                // The build verifies the bytes. AppKit reads each PNG when its view needs it.
                let image = NSImage(byReferencing: url)
                image.size = NSSize(width: display.width, height: display.height)
                prepared[product.id] = image
            }
            records = Dictionary(uniqueKeysWithValues: manifest.products.map { ($0.id, $0) })
            images = prepared
            isReady = true
        } catch {
            self.error = String(localized: "Product images could not be loaded. Please rebuild the app.")
        }
    }
}
