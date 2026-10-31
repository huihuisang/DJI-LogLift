import SwiftUI

struct StudioPreviewOptions: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        content
            .preferredColorScheme(appearance)
            .environment(\.studioReduceMotionPreview, CommandLine.arguments.contains("--reduce-motion-preview"))
        #else
        content
        #endif
    }

    #if DEBUG
    private var appearance: ColorScheme? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--studio-appearance"), arguments.indices.contains(index + 1) else {
            return nil
        }
        switch arguments[index + 1] {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }
    #endif
}

private struct StudioReduceMotionPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var studioReduceMotionPreview: Bool {
        get { self[StudioReduceMotionPreviewKey.self] }
        set { self[StudioReduceMotionPreviewKey.self] = newValue }
    }
}

@propertyWrapper
struct StudioReducedMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var systemPreference
    @Environment(\.studioReduceMotionPreview) private var previewPreference

    var wrappedValue: Bool { systemPreference || previewPreference }
}
