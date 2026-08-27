import SwiftUI

enum AppTheme {
    static let screenBackground = Color(.systemBackground)
    static let groupedBackground = Color(.systemGroupedBackground)
    static let secondaryFill = Color(.secondarySystemFill)
    static let tertiaryFill = Color(.tertiarySystemFill)
    static let separator = Color(.separator)
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
}
