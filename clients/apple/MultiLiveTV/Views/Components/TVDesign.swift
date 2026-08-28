import SwiftUI

#if os(tvOS)
enum TVDesign {
    static let screenPadding: CGFloat = AppTheme.screenPadding
    static let shelfSpacing: CGFloat = 40
    static let cardSpacing: CGFloat = 28
    static let cardWidth: CGFloat = 236
    static let cardHeight: CGFloat = 354
    static let focusScale: CGFloat = 1.10
    static let cornerRadius: CGFloat = AppTheme.posterRadius
    static let heroHeight: CGFloat = 560
}
#endif

#if os(tvOS)
struct TVFocusScaleEffect: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? TVDesign.focusScale : 1.0)
            .shadow(
                color: .black.opacity(isFocused ? 0.55 : 0.18),
                radius: isFocused ? 28 : 8,
                y: isFocused ? 16 : 6
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isFocused)
    }
}

private struct TVChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension View {
    func tvFocusScale(_ isFocused: Bool) -> some View {
        modifier(TVFocusScaleEffect(isFocused: isFocused))
    }

    func tvFocusChrome(_ isFocused: Bool) -> some View {
        self
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .tvFocusScale(isFocused)
    }

    func tvChipFocusChrome() -> some View {
        self
            .buttonStyle(TVChipButtonStyle())
            .fixedSize()
            .contentShape(Capsule())
            .focusEffectDisabled()
    }
}
#endif
