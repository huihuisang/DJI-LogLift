import SwiftUI

struct AjiguPromotionLink: View {
    @State private var hovered = false
    @FocusState private var focused: Bool
    @StudioReducedMotion private var reduceMotion

    private var resourceBundle: Bundle { Bundle(for: AjiguPromotionResources.self) }

    var body: some View {
        Link(destination: URL(string: "https://ajigu.com/")!) {
            HStack(alignment: .center, spacing: 12) {
                Image("AjiguMascot", bundle: resourceBundle)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "ajigu")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("We make other useful apps, too.", bundle: resourceBundle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(StudioPalette.accent)
                    .padding(.leading, 8)
                    .offset(x: hovered && !reduceMotion ? 2 : 0)
            }
            .padding(8)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background(.primary.opacity(hovered ? 0.025 : 0), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .focused($focused)
        .fixedSize()
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(focused ? Color.primary.opacity(0.55) : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .accessibilityLabel(Text("Explore more apps at ajigu.com", bundle: resourceBundle))
        .accessibilityIdentifier("gallery-more-apps")
        .help(Text("Explore more apps at ajigu.com", bundle: resourceBundle))
        .onHover { hovered = $0 }
        .animation(StudioMotion.feedback(reduceMotion: reduceMotion), value: hovered)
    }
}

private final class AjiguPromotionResources {}
