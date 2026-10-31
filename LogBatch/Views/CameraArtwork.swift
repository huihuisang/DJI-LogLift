import SwiftUI

struct CameraArtwork: View {
    let id: String
    let library: ProductArtworkLibrary

    var body: some View {
        Group {
            if let image = library.images[id] {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "camera").font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityHidden(true)
    }
}

struct CameraHeroArtwork: View {
    let id: String
    let library: ProductArtworkLibrary
    let namespace: Namespace.ID
    let isSource: Bool
    @StudioReducedMotion private var reduceMotion

    var body: some View {
        if reduceMotion {
            CameraArtwork(id: id, library: library)
        } else {
            CameraArtwork(id: id, library: library)
                .matchedGeometryEffect(id: "camera-" + id, in: namespace, isSource: isSource)
        }
    }
}

