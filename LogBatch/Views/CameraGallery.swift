import LogBatchCore
import SwiftUI

struct CameraGallery: View {
    let store: BatchStore
    let artwork: ProductArtworkLibrary
    let namespace: Namespace.ID
    let isVisible: Bool
    let choose: (DJIProduct) -> Void
    @State private var category = CameraCategory.all
    @State private var query = ""
    @Environment(CameraOrderStore.self) private var cameraOrder
    @Namespace private var categoryNamespace
    @StudioReducedMotion private var reduceMotion

    private var products: [DJIProduct] {
        cameraOrder.orderedProducts((store.catalog?.products ?? []).filter {
            category.includes($0) && (query.isEmpty || $0.name.localizedStandardContains(query))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Start with your camera.")
                            .font(.system(size: 42, weight: .semibold)).tracking(-1.4)
                        Text("Choose a model. Its official LUT is already here.")
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    AjiguPromotionLink()
                }
                HStack(spacing: 6) {
                    ForEach(CameraCategory.allCases) { item in
                        Button {
                            withAnimation(reduceMotion ? nil : StudioMotion.state(reduceMotion: false)) { category = item }
                        } label: {
                            Text(verbatim: item.title).font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .contentShape(Capsule())
                                .background {
                                    if category == item {
                                        if reduceMotion {
                                            Capsule().fill(.primary.opacity(0.085))
                                        } else {
                                            Capsule().fill(.primary.opacity(0.085))
                                                .matchedGeometryEffect(id: "category", in: categoryNamespace)
                                        }
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("category-" + item.rawValue)
                        .accessibilityAddTraits(category == item ? [.isSelected] : [])
                    }
                    Spacer()
                    if !artwork.isReady { ProgressView().controlSize(.small).accessibilityLabel("Loading cameras…") }
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find your camera", text: $query).textFieldStyle(.plain)
                            .accessibilityIdentifier("gallery-search")
                    }
                    .padding(12).frame(width: 220)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
                }
            }
            .padding(.bottom, 24)
            .background {
                Rectangle().fill(.background)
                    .padding(.horizontal, -40).padding(.top, -18)
                    .ignoresSafeArea(.container, edges: .top)
            }
            .zIndex(1)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 18)], spacing: 18) {
                        ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                            CameraTile(product: product, artwork: artwork, namespace: namespace,
                                       isSource: isVisible, index: index,
                                       isSupported: store.catalog?.luts(for: product.id).contains(where: \.canConvertToRec709) == true,
                                       canPin: index > 0, pin: {
                                withAnimation(reduceMotion ? nil : StudioMotion.state(reduceMotion: false)) {
                                    if cameraOrder.moveToFront(product.id, among: products) {
                                        scroll.scrollTo("camera-gallery-top", anchor: .top)
                                    }
                                }
                            }) {
                                choose(product)
                            }
                        }
                    }
                    .padding(.top, 8).padding(.bottom, 28)
                    .id("camera-gallery-top")
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("camera-gallery-scroll")
                .overlay {
                    if products.isEmpty { ContentUnavailableView.search(text: query) }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "lock.shield").font(.system(size: 12))
                Text("All processing stays on your Mac.")
                Spacer()
                Text(verbatim: String(store.catalog?.products.count ?? 0)).monospacedDigit()
                Text("Cameras")
                Text(verbatim: "·").padding(.horizontal, 4)
                Text(verbatim: String(store.catalog?.luts.count ?? 0)).monospacedDigit()
                Text("Bundled LUTs")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.top, 12)
            .background { Rectangle().fill(.background).padding(.bottom, -24) }
            .zIndex(1)
        }
        .padding(.horizontal, 40).padding(.top, 18).padding(.bottom, 24)
        .background(GalleryInitialFocus())
    }
}

private struct CameraTile: View {
    let product: DJIProduct
    let artwork: ProductArtworkLibrary
    let namespace: Namespace.ID
    let isSource: Bool
    let index: Int
    let isSupported: Bool
    let canPin: Bool
    let pin: () -> Void
    let action: () -> Void
    @State private var hovered = false
    @State private var appeared = false
    @FocusState private var focused: Bool
    @FocusState private var pinFocused: Bool
    @StudioReducedMotion private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var showsPin: Bool { canPin && (hovered || focused || pinFocused) }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                VStack(spacing: 18) {
                    CameraHeroArtwork(id: product.id, library: artwork, namespace: namespace, isSource: isSource)
                        .frame(height: 140)
                        .scaleEffect(hovered && !reduceMotion ? 1.045 : 1)
                        .offset(y: hovered && !reduceMotion ? -4 : 0)
                        .padding(.horizontal, 22).padding(.top, 12)
                    VStack(spacing: 5) {
                        Text(verbatim: product.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if artwork.records[product.id]?.representation == "official-family" {
                            Text("Series image").font(.system(size: 10)).foregroundStyle(.secondary)
                        } else if !isSupported {
                            Text("Reference LUTs").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 34, alignment: .top)
                }
                .padding(.top, 16).padding(.bottom, 12).frame(maxWidth: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 24))
            }
            .buttonStyle(.plain).focused($focused)
            .accessibilityLabel(Text(verbatim: product.name))
            .accessibilityIdentifier("camera-card-" + product.id)
            .help(Text(verbatim: product.name))

            Group {
                if canPin {
                    Button("Pin to Top", systemImage: "pin.fill", action: pin)
                        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.small)
                        .tint(StudioPalette.accent)
                        .focused($pinFocused)
                        .accessibilityLabel(Text("Pin \(product.name) to Top"))
                        .accessibilityIdentifier("camera-pin-" + product.id)
                        .help("Pin to Top")
                        .opacity(showsPin ? 1 : 0)
                        .offset(y: showsPin || reduceMotion ? 0 : 8)
                        .allowsHitTesting(showsPin)
                        .disabled(!showsPin)
                        .accessibilityHidden(!showsPin)
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(height: 24)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(.primary.opacity(hovered ? 0.065 : 0.028), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(focused || pinFocused || contrast == .increased ? Color.primary.opacity(0.55) : Color.clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(Double(-index))
        .disabled(!artwork.isReady)
        .onHover { hovered = $0 }
        .animation(StudioMotion.feedback(reduceMotion: reduceMotion), value: hovered)
        .animation(StudioMotion.feedback(reduceMotion: reduceMotion), value: showsPin)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 10)
        .onAppear {
            withAnimation(StudioMotion.state(reduceMotion: reduceMotion).delay(reduceMotion ? 0 : Double(index % 6) * 0.03)) {
                appeared = true
            }
        }
    }
}
