import AppKit
import SwiftUI

struct PreviewPane: View {
    let store: BatchStore
    @State private var reveal: CGFloat = 0.5
    @State private var rotationSteps = 0
    @StudioReducedMotion private var reduceMotion

    var body: some View {
        Group {
            if store.isLoadingPreview {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Preparing preview…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } else if let images = store.playback.frames ?? store.preview {
                GeometryReader { geometry in
                    ZStack {
                        Color.black
                        previewImage(images.converted, in: geometry.size)
                        previewImage(images.original, in: geometry.size)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: geometry.size.width * reveal)
                            }
                        HStack {
                            Button {
                                withAnimation(reduceMotion ? nil : StudioMotion.state(reduceMotion: false)) { reveal = 1 }
                            } label: { Text("Original") }
                            Spacer()
                            Button {
                                withAnimation(reduceMotion ? nil : StudioMotion.state(reduceMotion: false)) { reveal = 0 }
                            } label: { Text("Rec.709 Preview") }
                        }
                        .buttonStyle(.plain).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white).padding(16)
                        .background(alignment: .top) {
                            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        comparisonHandle(height: geometry.size.height)
                            .position(x: geometry.size.width * reveal, y: geometry.size.height / 2)
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("comparison")).onChanged { value in
                                withTransaction(Transaction(animation: nil)) {
                                    reveal = min(1, max(0, value.location.x / geometry.size.width))
                                }
                            })
                            .focusable()
                            .focusEffectDisabled()
                            .onMoveCommand { direction in
                                if direction == .left { reveal = max(0, reveal - 0.1) }
                                if direction == .right { reveal = min(1, reveal + 0.1) }
                            }
                            .accessibilityRepresentation {
                                Slider(value: $reveal, in: 0...1) {
                                    Text("Compare original and converted")
                                }
                                .accessibilityValue(Text(reveal, format: .percent.precision(.fractionLength(0))))
                                .accessibilityIdentifier("comparison-handle")
                            }
                    }
                    .coordinateSpace(name: "comparison")
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 10) {
                            PreviewPlaybackControls(playback: store.playback)
                                .disabled(store.isProcessing)
                            rotationButton.tint(nil)
                        }
                        .padding(16)
                    }
                }
            } else if let error = store.previewError {
                ContentUnavailableView {
                    Label("Preview Unavailable", systemImage: "exclamationmark.triangle")
                } description: { Text(verbatim: error) }
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 34, weight: .ultraLight)).foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        Text("Drop your footage here.").font(.system(size: 21, weight: .medium)).tracking(-0.4)
                        Text("Or add videos to start with a before-and-after preview.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 10) {
                        Button("Add Videos") { store.chooseVideos() }
                            .buttonStyle(StudioButtonStyle())
                            .disabled(store.isProcessing || store.isImporting)
                            .accessibilityIdentifier("preview-add-videos")
                        Label("On your Mac", systemImage: "lock.shield")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: store.previewID) { reveal = 0.5 }
        .onChange(of: store.selectedItemID) { rotationSteps = 0 }
    }

    @ViewBuilder
    private var rotationButton: some View {
        let button = Button {
            rotationSteps += 1
        } label: {
            Label {
                Text("Rotate preview 90° clockwise")
            } icon: {
                Image(systemName: "rotate.right")
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 24, height: 24)
            .padding(.horizontal, 6)
        }
        .help("Rotate preview 90° clockwise")
        .accessibilityIdentifier("preview-rotate-clockwise")

        if #available(macOS 26.0, *) {
            button.buttonStyle(.glass).buttonBorderShape(.capsule)
        } else {
            button.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }

    private func previewImage(_ image: CGImage, in size: CGSize) -> some View {
        let fit = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let fittedSize = CGSize(width: CGFloat(image.width) * fit, height: CGFloat(image.height) * fit)
        let rotationScale = rotationSteps % 2 == 1
            ? min(size.width / max(fittedSize.height, 1), size.height / max(fittedSize.width, 1)) : 1
        return Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
            .frame(width: fittedSize.width, height: fittedSize.height)
            .rotationEffect(.degrees(Double(rotationSteps) * 90))
            .scaleEffect(rotationScale)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: rotationSteps)
            .frame(width: size.width, height: size.height)
    }

    private func comparisonHandle(height: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.85)).frame(width: 1, height: height)
            RoundedRectangle(cornerRadius: 10).fill(.white)
                .frame(width: 28, height: 42)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                .overlay {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.black)
                }
        }
        .frame(width: 40, height: height).contentShape(Rectangle())
    }
}

