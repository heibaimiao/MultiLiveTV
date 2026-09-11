import SwiftUI

struct CategoryTabButton: View {
    enum Size {
        case medium
        case secondary
        case small

        var font: Font {
            switch self {
            case .medium:
                #if os(tvOS)
                .title3.weight(.semibold)
                #else
                .subheadline.weight(.semibold)
                #endif
            case .secondary:
                #if os(tvOS)
                .headline.weight(.semibold)
                #else
                .body.weight(.semibold)
                #endif
            case .small:
                #if os(tvOS)
                .body.weight(.medium)
                #else
                .caption.weight(.semibold)
                #endif
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .medium: 16
            case .secondary: 14
            case .small: 12
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .medium: 10
            case .secondary: 9
            case .small: 7
            }
        }

        var usesAccentSelection: Bool { self == .secondary }
    }

    let label: String
    let isActive: Bool
    var isFocused: Bool = false
    var disabled: Bool = false
    var size: Size = .medium
    var systemImage: String? = nil
    var badge: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(size.font)
                }
                Text(label)
                    .font(size.font)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                if let badge {
                    Text(badge)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isFocused ? Color.black.opacity(0.55) : AppTheme.textTertiary)
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(backgroundColor, in: Capsule())
        }
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
        #if os(tvOS)
        .tvChipFocusChrome()
        #else
        .buttonStyle(.plain)
        #endif
    }

    private var foregroundColor: Color {
        if isFocused {
            return .black
        }
        if isActive, size.usesAccentSelection {
            return AppTheme.accent
        }
        if isActive {
            return AppTheme.textPrimary
        }
        return AppTheme.textSecondary
    }

    private var backgroundColor: Color {
        if isFocused {
            return .white
        }
        if isActive, size.usesAccentSelection {
            return AppTheme.accent.opacity(0.22)
        }
        if isActive {
            return AppTheme.secondaryFill
        }
        return .clear
    }
}

enum CategoryFocus {
    static let prefix = "c:"
    static let search = "c:search"

    static func primary(_ slug: String) -> String { "c:p:\(slug)" }
    static func secondary(_ slug: String) -> String { "c:s:\(slug)" }

    static func isCategory(_ id: String?) -> Bool {
        id?.hasPrefix(prefix) == true
    }

    static func preferredKey(
        primary: [SlugCategory],
        activeSlug: String?,
        activeParentSlug: String?,
        showSecondary: Bool
    ) -> String {
        if showSecondary, let parentSlug = activeParentSlug {
            return secondary(activeSlug ?? parentSlug)
        }
        if let activeSlug {
            return Self.primary(activeSlug)
        }
        return Self.primary("all")
    }
}

struct CategoryTabs: View {
    let primary: [SlugCategory]
    let secondary: [SlugCategory]
    let activeSlug: String?
    let activeParentSlug: String?
    var pending: Bool = false
    var focusRequest: Int = 0
    var focusedId: FocusState<String?>.Binding
    var onSearch: (() -> Void)? = nil
    let onSelect: (String?) -> Void

    private var showSecondary: Bool {
        !secondary.isEmpty && activeParentSlug != nil
    }

    private var preferredFocusKey: String {
        CategoryFocus.preferredKey(
            primary: primary,
            activeSlug: activeSlug,
            activeParentSlug: activeParentSlug,
            showSecondary: showSecondary
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            primaryRow

            if showSecondary, let activeParentSlug {
                tabRow(prefix: "s", spacing: 12, fadeTrailing: true) {
                    CategoryTabButton(
                        label: "全部",
                        isActive: activeSlug == activeParentSlug,
                        isFocused: focusedId.wrappedValue == CategoryFocus.secondary(activeParentSlug),
                        disabled: pending,
                        size: .secondary
                    ) { onSelect(activeParentSlug) }
                    .tvChipFocused(focusedId, equals: CategoryFocus.secondary(activeParentSlug))

                    ForEach(secondary) { category in
                        CategoryTabButton(
                            label: category.label,
                            isActive: activeSlug == category.slug,
                            isFocused: focusedId.wrappedValue == CategoryFocus.secondary(category.slug),
                            disabled: pending,
                            size: .secondary
                        ) { onSelect(category.slug) }
                        .tvChipFocused(focusedId, equals: CategoryFocus.secondary(category.slug))
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.screenPadding)
        #if os(tvOS)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .focusSection()
        .onChange(of: focusRequest) { _, _ in
            guard !preferredFocusKey.isEmpty else { return }
            focusedId.wrappedValue = preferredFocusKey
        }
        #else
        .padding(.vertical, 8)
        #endif
    }

    @ViewBuilder
    private var primaryRow: some View {
        #if os(tvOS)
        HStack(alignment: .center, spacing: 16) {
            BrandLogo(height: 36)
            tabRow(prefix: "p", spacing: 8, trapsFocus: false) {
                primaryChips
            }
            if let onSearch {
                CategoryTabButton(
                    label: "搜索",
                    isActive: false,
                    isFocused: focusedId.wrappedValue == CategoryFocus.search,
                    systemImage: "magnifyingglass"
                ) { onSearch() }
                .tvChipFocused(focusedId, equals: CategoryFocus.search)
            }
        }
        .focusSection()
        #else
        HStack(alignment: .center, spacing: 12) {
            BrandLogo(height: 28)
            tabRow(prefix: "p") {
                primaryChips
            }
        }
        #endif
    }

    @ViewBuilder
    private var primaryChips: some View {
        CategoryTabButton(
            label: "全部",
            isActive: activeSlug == nil,
            isFocused: focusedId.wrappedValue == CategoryFocus.primary("all"),
            disabled: pending
        ) { onSelect(nil) }
        .tvChipFocused(focusedId, equals: CategoryFocus.primary("all"))

        ForEach(primary) { category in
            CategoryTabButton(
                label: category.label,
                isActive: activeSlug == category.slug || activeParentSlug == category.slug,
                isFocused: focusedId.wrappedValue == CategoryFocus.primary(category.slug),
                disabled: pending
            ) { onSelect(category.slug) }
            .tvChipFocused(focusedId, equals: CategoryFocus.primary(category.slug))
        }
    }

    @ViewBuilder
    private func tabRow<Content: View>(
        prefix: String,
        spacing: CGFloat = 8,
        fadeTrailing: Bool = false,
        trapsFocus: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let row = ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: spacing) {
                content()
            }
        }
        .contentMargins(.all, 0, for: .scrollContent)
        .contentMargins(.all, 0)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .trailing) {
            if fadeTrailing {
                LinearGradient(
                    colors: [.clear, AppTheme.screenBackground],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 44)
                .allowsHitTesting(false)
            }
        }
        #if os(tvOS)
        if trapsFocus {
            row.focusSection()
        } else {
            row
        }
        #else
        row
        #endif
    }
}
