import LogBatchCore
import SwiftUI

struct ContentView: View {
    @State private var store = BatchStore(notifications: ExportNotifications.shared)
    @State private var artwork = ProductArtworkLibrary()
    @State private var showsGallery = true
    @Namespace private var cameraNamespace
    @StudioReducedMotion private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var selectedProduct: DJIProduct? {
        store.catalog?.products.first { $0.id == store.selectedProductID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let message = store.message ?? artwork.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(verbatim: message).font(.callout)
                    Spacer()
                    if store.message != nil {
                        Button("Dismiss", systemImage: "xmark") { store.message = nil }.labelStyle(.iconOnly)
                    }
                }
                .padding(14).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 40)
            }

            ZStack {
                CameraGallery(store: store, artwork: artwork, namespace: cameraNamespace, isVisible: showsGallery) { product in
                    guard !store.isProcessing else { return }
                    store.selectedProductID = product.id
                    withAnimation(StudioMotion.hero(reduceMotion: reduceMotion)) { showsGallery = false }
                }
                .opacity(showsGallery ? 1 : 0)
                .allowsHitTesting(showsGallery)
                .disabled(!showsGallery)
                .accessibilityElement(children: .contain)
                .accessibilityHidden(!showsGallery)

                if let product = selectedProduct {
                    ConversionWorkspace(store: store, product: product, artwork: artwork, namespace: cameraNamespace,
                                        isHeroSource: !showsGallery, showGallery: showGallery)
                        .opacity(showsGallery ? 0 : 1)
                        .allowsHitTesting(!showsGallery)
                        .disabled(showsGallery)
                        .accessibilityElement(children: .contain)
                        .accessibilityHidden(showsGallery)
                }
            }
        }
        .background(.background)
        .tint(StudioPalette.accent)
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { url in
            do {
                let request = try FinderImportRequest.consume(url)
                store.importFromFinder(request.files)
                showsGallery = false
            } catch { store.message = error.localizedDescription }
        }
        .task { await artwork.prepare() }
        .onChange(of: store.selectedProductID) { store.selectCamera() }
        .onChange(of: store.selectedLUTID) { store.cancelExportConfirmation() }
        .onChange(of: showsGallery) { if showsGallery { store.playback.pause() } }
        .onChange(of: scenePhase) { if scenePhase != .active { store.playback.pause() } }
        .onChange(of: store.isProcessing) { if store.isProcessing { store.playback.pause() } }
        .onDisappear { store.playback.pause() }
        .task(id: "\(showsGallery):\(store.previewID)") {
            if !showsGallery { await store.loadPreview() }
        }
        .onExitCommand {
            if !store.isProcessing { showsGallery = true }
        }
    }

    private func showGallery() {
        withAnimation(StudioMotion.hero(reduceMotion: reduceMotion)) { showsGallery = true }
    }
}

