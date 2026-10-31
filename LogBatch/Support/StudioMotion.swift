import SwiftUI

enum StudioPalette {
    static let accent = Color(red: 0.82, green: 0.24, blue: 0.08)
}

enum StudioMotion {
    static func hero(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.5, bounce: 0.2)
    }

    static func feedback(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.16, bounce: 0.1)
    }

    static func state(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.25, bounce: 0.1)
    }
}

struct StudioButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    @StudioReducedMotion private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18).padding(.vertical, 12)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(prominent ? StudioPalette.accent : Color.primary.opacity(configuration.isPressed ? 0.1 : 0.055))
            }
            .opacity(isEnabled ? 1 : 0.36)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(StudioMotion.feedback(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

struct StudioSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(.background, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(.primary.opacity(contrast == .increased ? 0.4 : 0.07), lineWidth: 1)
            }
    }
}

