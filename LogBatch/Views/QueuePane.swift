import AppKit
import SwiftUI

struct QueuePane: View {
    @Bindable var store: BatchStore
    @State private var showsClearConfirmation = false
    @StudioReducedMotion private var reduceMotion

    private var selection: Binding<UUID?> {
        Binding(get: { store.selectedItemID }, set: { store.selectItem($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Your clips").font(.system(size: 14, weight: .semibold))
                Text(verbatim: String(store.items.count))
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.primary.opacity(0.055), in: Capsule())
                Spacer()
                if store.isImporting { ProgressView().controlSize(.mini) }
                Button("Clear Queue", systemImage: "trash") { showsClearConfirmation = true }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                    .disabled(store.isProcessing || store.isImporting || store.items.isEmpty)
                    .accessibilityIdentifier("queue-clear")
                    .help("Clear Queue")
            }.padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
            List(selection: selection) {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                    ClipQueueRow(item: item, index: index, canRemove: !store.isProcessing && !store.isImporting) {
                        store.remove(item.id)
                    }
                    .tag(item.id)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("clip-row-" + item.id.uuidString)
                    .task(id: item.id) { await store.loadClipDetails(for: item.id) }
                    .contextMenu {
                        if let output = item.output {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                        }
                        Button("Remove Clip", systemImage: "trash", role: .destructive) { store.remove(item.id) }
                            .disabled(store.isProcessing || store.isImporting)
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .animation(reduceMotion ? nil : StudioMotion.state(reduceMotion: false), value: store.items.count)
            .onDeleteCommand {
                if let id = store.selectedItemID { store.remove(id) }
            }
            .overlay {
                if store.items.isEmpty {
                    Text("Your clips will appear here.").font(.system(size: 12))
                        .foregroundStyle(.tertiary).allowsHitTesting(false)
                }
            }
            .accessibilityIdentifier("batch-queue")
        }
        .modifier(StudioSurface())
        .alert("Clear all clips?", isPresented: $showsClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Queue", role: .destructive) { store.clear() }
        } message: {
            Text("This removes all clips from the queue. Original and exported files stay unchanged.")
        }
    }
}

private struct ClipQueueRow: View {
    let item: BatchItem
    let index: Int
    let canRemove: Bool
    let remove: () -> Void
    @State private var isHovered = false
    @StudioReducedMotion private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: String(format: "%02d", index + 1))
                .font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(.tertiary).frame(width: 20)
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: item.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Group {
                    if let date = item.recordingDate {
                        Text("Recorded \(date.formatted(date: .abbreviated, time: .shortened))")
                    } else {
                        Text("Recording date unknown")
                    }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                .opacity(item.hasLoadedDetails ? 1 : 0)
                .accessibilityHidden(!item.hasLoadedDetails)
                if let error = item.error {
                    Text(verbatim: error).font(.system(size: 10)).foregroundStyle(.red).lineLimit(2).help(error)
                }
            }
            Spacer(minLength: 12)
            if item.status == .processing {
                ProgressView(value: item.progress).frame(width: 80).controlSize(.small)
                    .animation(reduceMotion ? nil : .linear(duration: 0.12), value: item.progress)
            }
            if item.status == .completed {
                Text(verbatim: item.status.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color(red: 0.12, green: 0.48, blue: 0.28), in: Capsule())
            } else {
                Text(verbatim: item.status.title).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Button("Remove Clip", systemImage: "trash", role: .destructive, action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 28)
                .opacity(isHovered ? 1 : 0)
                .offset(x: isHovered || reduceMotion ? 0 : 10)
                .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.24), value: isHovered)
                .allowsHitTesting(isHovered && canRemove)
                .accessibilityHidden(!isHovered)
                .disabled(!canRemove || !isHovered)
                .help("Remove Clip")
                .accessibilityIdentifier("clip-remove-" + item.id.uuidString)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityAction(named: Text("Remove Clip")) {
            if canRemove { remove() }
        }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.06))
            if let image = item.thumbnail {
                Image(decorative: image, scale: 1)
                    .resizable().scaledToFit()
            } else {
                Image(systemName: "film")
                    .font(.system(size: 20)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}
