import Foundation
import LogBatchCore

enum LUTChoiceTitle {
    static func title(for lut: LUTDefinition, among choices: [LUTDefinition]) -> String {
        let title = base(lut)
        if choices.filter({ base($0) == title }).count > 1 {
            return title + " · " + URL(fileURLWithPath: lut.originalName).lastPathComponent
        }
        return title
    }

    private static func base(_ lut: LUTDefinition) -> String {
        let output: String
        switch lut.outputProfile {
        case "rec709": output = "Rec.709"
        case "rec2020HLG": output = "Rec.2020 HLG"
        case "dlog": output = "D-Log"
        case "sRGB": output = "sRGB"
        default: output = String(localized: "Unspecified")
        }
        let style = lut.style == "vivid" ? String(localized: "Vivid") : String(localized: "Standard")
        let dimension = lut.dimension.map { "\($0)³" } ?? lut.shaperDimension.map { "\($0)¹" } ?? ""
        return [lut.profileName + " → " + output, style, dimension, lut.version].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
