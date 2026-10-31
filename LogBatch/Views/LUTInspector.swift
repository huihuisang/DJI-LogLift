import LogBatchCore
import SwiftUI

struct LUTInspector: View {
    @Bindable var store: BatchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Color Conversion").font(.system(size: 12, weight: .semibold))
                Spacer()
                Image(systemName: "slider.horizontal.3").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if store.availableLUTs.count > 1 {
                Picker("Conversion LUT", selection: $store.selectedLUTID) {
                    ForEach(store.availableLUTs) { lut in
                        Text(verbatim: LUTChoiceTitle.title(for: lut, among: store.availableLUTs)).tag(Optional(lut.id))
                    }
                }
                .labelsHidden().pickerStyle(.menu).disabled(store.isProcessing)
                .accessibilityIdentifier("conversion-lut-picker")
            }
            if let lut = store.selectedLUT {
                HStack(spacing: 8) {
                    Text(verbatim: lut.profileName).font(.system(size: 12, weight: .medium))
                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Text(verbatim: lut.outputProfileName).font(.system(size: 12, weight: .medium))
                }
                .padding(12).frame(maxWidth: .infinity)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    if lut.style == "vivid" { Text("Vivid") } else { Text("Standard") }
                    Spacer()
                    Text(verbatim: lut.version)
                    if let size = lut.dimension { Text(verbatim: "\(size)³") }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 2)
            if store.selectedLUT?.canConvertToRec709 == true {
                Text("Do not apply a conversion LUT to Normal, HLG, or previously converted videos.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Reference LUTs", systemImage: "archivebox").font(.system(size: 12, weight: .medium))
                Text("This LUT is included for reference. The first version exports 3D Log-to-Rec.709 conversions only.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let lut = store.selectedLUT,
               let package = store.catalog?.packages.first(where: { $0.id == lut.packageID }) {
                Link("DJI Official Source", destination: package.sourcePage).font(.system(size: 10))
            }
        }
    }

}

private extension LUTDefinition {
    var outputProfileName: String {
        switch outputProfile {
        case "rec709": "Rec.709"
        case "rec2020HLG": "Rec.2020 HLG"
        case "dlog": "D-Log"
        case "sRGB": "sRGB"
        default: String(localized: "Unspecified")
        }
    }
}
