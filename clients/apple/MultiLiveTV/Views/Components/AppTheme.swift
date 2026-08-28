import SwiftUI

enum AppTheme {
    /// Warm off-black. Pure black flattens posters and focus shadows.
    static let screenBackground = Color(red: 0.055, green: 0.055, blue: 0.062)
    static let groupedBackground = Color(red: 0.085, green: 0.085, blue: 0.092)
    static let elevated = Color(red: 0.125, green: 0.125, blue: 0.135)
    static let secondaryFill = Color.white.opacity(0.10)
    static let tertiaryFill = Color.white.opacity(0.06)
    static let separator = Color.white.opacity(0.14)

    /// Cinema amber, Infuse-adjacent. One accent for the whole app.
    static let accent = Color(red: 0.93, green: 0.62, blue: 0.20)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary = Color.white.opacity(0.48)

    static let posterRadius: CGFloat = 8
    static let chipRadius: CGFloat = 6
    static let controlRadius: CGFloat = 12

    #if os(tvOS)
    static let screenPadding: CGFloat = 80
    static let gridSpacing: CGFloat = 28
    static let cardMinWidth: CGFloat = 240
    #else
    static let screenPadding: CGFloat = 20
    static let gridSpacing: CGFloat = 16
    static let cardMinWidth: CGFloat = 160
    #endif
}

struct InvisibleFocusButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

struct ScreenBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.screenBackground)
    }
}

extension View {
    func screenBackground() -> some View {
        modifier(ScreenBackgroundModifier())
    }

    func hiddenFocusChrome() -> some View {
        self
            .buttonStyle(InvisibleFocusButtonStyle())
            #if os(tvOS)
            .focusEffectDisabled(true)
            #endif
            #if os(iOS)
            .hoverEffectDisabled(true)
            #endif
    }

    func cinemaListChrome() -> some View {
        self
            #if os(iOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(AppTheme.screenBackground)
    }

    @ViewBuilder
    func iPadRefreshable(_ action: @escaping () async -> Void) -> some View {
        #if os(iOS)
        refreshable { await action() }
        #else
        self
        #endif
    }

    @ViewBuilder
    func iPadFillScrollRefreshable(_ action: @escaping () async -> Void) -> some View {
        #if os(iOS)
        GeometryReader { proxy in
            ScrollView {
                self.frame(width: proxy.size.width, height: proxy.size.height)
            }
            .refreshable { await action() }
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func tvFocusSection() -> some View {
        #if os(tvOS)
        focusSection()
        #else
        self
        #endif
    }

    func tvChipFocused<Value: Hashable>(_ binding: FocusState<Value>.Binding, equals value: Value) -> some View {
        #if os(tvOS)
        self
            .focused(binding, equals: value)
            .focusEffectDisabled()
        #else
        self.focused(binding, equals: value)
        #endif
    }
}
