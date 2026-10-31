import LogBatchCore
import SwiftUI

struct ConversionWorkspace: View {
    @Bindable var store: BatchStore
    let product: DJIProduct
    let artwork: ProductArtworkLibrary
    let namespace: Namespace.ID
    let isHeroSource: Bool
    let showGallery: () -> Void
    @State private var dropTargeted = false
    @StudioReducedMotion private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Text("A little less Log. A lot more life.")
                    .font(.system(size: 28, weight: .semibold)).tracking(-0.7)
                Spacer(minLength: 20)
                Button("Change Camera", systemImage: "square.grid.2x2", action: showGallery)
                    .buttonStyle(StudioButtonStyle()).disabled(store.isProcessing)
                    .accessibilityIdentifier("workspace-change-camera")
                Button("Add Videos", systemImage: "plus") { store.chooseVideos() }
                    .buttonStyle(StudioButtonStyle()).keyboardShortcut("o", modifiers: .command)
                    .disabled(store.isProcessing || store.isImporting)
                    .accessibilityIdentifier("workspace-add-videos")
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 18) {
                    PreviewPane(store: store)
                        .frame(minHeight: 210, maxHeight: .infinity)
                        .modifier(StudioSurface())
                        .overlay {
                            RoundedRectangle(cornerRadius: 24)
                                .strokeBorder(dropTargeted ? StudioPalette.accent : .clear, lineWidth: 2)
                        }
                    QueuePane(store: store)
                        .frame(minHeight: 170, idealHeight: 210, maxHeight: 240)
                }
                .frame(maxWidth: .infinity)
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(spacing: 22) {
                                CameraHeroArtwork(id: product.id, library: artwork, namespace: namespace, isSource: isHeroSource)
                                    .frame(height: min(148, geometry.size.height * 0.2))
                                VStack(spacing: 5) {
                                    Text(verbatim: product.name).font(.system(size: 20, weight: .semibold)).tracking(-0.5)
                                    if artwork.records[product.id]?.representation == "official-family" {
                                        Text("Series image").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                LUTInspector(store: store)
                            }
                            .padding(.bottom, 24)
                        }
                        .scrollIndicators(.hidden)
                        .id(product.id)
                        Divider()
                        ExportBar(store: store)
                            .padding(.top, 24)
                    }
                    .padding(24)
                }
                .frame(width: 336)
                .modifier(StudioSurface())
            }
        }
        .padding(.horizontal, 40).padding(.top, 16).padding(.bottom, 28)
        .dropDestination(for: URL.self) { urls, _ in
            guard !store.isProcessing && !store.isImporting else { return false }
            store.add(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .animation(StudioMotion.state(reduceMotion: reduceMotion), value: dropTargeted)
    }
}
