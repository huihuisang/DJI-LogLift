import CoreImage
import SwiftUI

struct ExportBar: View {
    @Bindable var store: BatchStore
    @StudioReducedMotion private var reduceMotion

    private var pendingCount: Int { store.items.count { $0.status != .completed } }
    private var allDone: Bool { !store.items.isEmpty && pendingCount == 0 }
    private var resourceBundle: Bundle { Bundle(for: ExportResourceToken.self) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Export", bundle: resourceBundle).font(.system(size: 18, weight: .semibold))
                Spacer(minLength: 8)
                summary.font(.system(size: 11)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("workspace-export-summary")
            }
            destination
            VStack(alignment: .leading, spacing: 16) {
                Text("HEVC · 10-bit · Rec.709", bundle: resourceBundle)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if store.isProcessing {
                    Button { store.cancel() } label: {
                        actionLabel("Cancel", systemImage: "stop.fill")
                    }
                    .buttonStyle(ExportButtonStyle(prominent: false))
                    .accessibilityIdentifier("workspace-cancel")
                } else {
                    Button { store.start() } label: {
                        actionLabel(store.showsExportSuccess ? "All done" : "Convert and Export",
                                    systemImage: store.showsExportSuccess ? "checkmark" : nil)
                    }
                    .buttonStyle(ExportButtonStyle(prominent: true))
                    .disabled(!store.canStart)
                    .accessibilityIdentifier("workspace-export")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Check the recording mode", isPresented: $store.showsExportConfirmation, titleVisibility: .visible) {
            Button("Convert and Export") { store.confirmExport() }
                .disabled(!store.canStart)
            Button("Cancel", role: .cancel) { store.cancelExportConfirmation() }
        } message: {
            Text("Only convert original \(store.selectedLUT?.profileName ?? "Log") clips. Normal, HLG, or previously converted videos can produce incorrect colors.")
        }
        .dialogSuppressionToggle("Don't ask again", isSuppressed: $store.suppressExportReminder)
        .animation(StudioMotion.state(reduceMotion: reduceMotion), value: store.isProcessing)
        .animation(StudioMotion.state(reduceMotion: reduceMotion), value: allDone)
        .animation(StudioMotion.state(reduceMotion: reduceMotion), value: store.showsExportSuccess)
    }

    @ViewBuilder
    private var summary: some View {
        if store.isProcessing {
            Text("Converting", bundle: resourceBundle)
        } else if allDone {
            Text("All done", bundle: resourceBundle)
        } else if pendingCount == 1 {
            Text("1 video pending", bundle: resourceBundle)
        } else {
            Text("\(pendingCount) videos pending", bundle: resourceBundle)
        }
    }

    private var destination: some View {
        Button { store.chooseOutput() } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 23, weight: .light)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Export destination", bundle: resourceBundle).font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        if let folder = store.outputDirectory {
                            Text(verbatim: folder.lastPathComponent)
                                .lineLimit(1).truncationMode(.middle)
                        } else {
                            Text("Choose Folder", bundle: resourceBundle)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(store.isProcessing)
        .help(store.outputDirectory?.path ?? String(localized: "Choose Folder"))
        .accessibilityIdentifier("workspace-output-folder")
    }

    private func actionLabel(_ title: LocalizedStringKey, systemImage: String?) -> some View {
        // Equal side insets keep the text centered independently of the icon.
        Text(title, bundle: resourceBundle)
            .font(.system(size: 16, weight: .semibold))
            .padding(.horizontal, 46)
            .frame(maxWidth: .infinity, minHeight: 56)
            .overlay(alignment: .leading) {
                Group {
                    if let systemImage {
                        Image(systemName: systemImage).font(.system(size: 17, weight: .semibold))
                    } else {
                        if let icon = ExportResourceToken.icon {
                            Image(nsImage: icon).renderingMode(.template).resizable().scaledToFit()
                        } else {
                            Image(systemName: "tray.and.arrow.up")
                                .font(.system(size: 19, weight: .medium))
                        }
                    }
                }
                .frame(width: 26, height: 26).padding(.leading, 16)
                .accessibilityHidden(true)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

private final class ExportResourceToken {
    @MainActor static let icon: NSImage? = {
        guard let data = Bundle(for: ExportResourceToken.self).image(forResource: "ExportIcon")?.tiffRepresentation,
              let source = CIImage(data: data) else { return nil }
        // The generated source is a luminance mask. Normalize it once for native template rendering.
        let scale = 64 / source.extent.width
        let mask = source.applyingFilter("CIMaskToAlpha").transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(mask, from: mask.extent) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: 26, height: 26))
        image.isTemplate = true
        return image
    }()
}

private struct ExportButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @StudioReducedMotion private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(prominent ? StudioPalette.accent : Color.primary.opacity(0.07))
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(StudioMotion.feedback(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
