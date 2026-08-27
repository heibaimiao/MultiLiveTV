import SwiftUI

#if os(tvOS)
enum TVDesign {
    static let screenPadding: CGFloat = 80
    static let shelfSpacing: CGFloat = 48
    static let cardSpacing: CGFloat = 40
    static let cardWidth: CGFloat = 260
    static let cardHeight: CGFloat = 390
    static let focusScale: CGFloat = 1.08
    static let cornerRadius: CGFloat = 12
    static let heroHeight: CGFloat = 420
}
#endif

#if os(tvOS)
struct TVFocusScaleEffect: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? TVDesign.focusScale : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: isFocused ? 24 : 0, y: isFocused ? 12 : 0)
            .animation(.easeOut(duration: 0.22), value: isFocused)
    }
}

extension View {
    func tvFocusScale(_ isFocused: Bool) -> some View {
        modifier(TVFocusScaleEffect(isFocused: isFocused))
    }
}
#endif
