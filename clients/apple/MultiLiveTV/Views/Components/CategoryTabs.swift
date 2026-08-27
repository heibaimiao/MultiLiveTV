import SwiftUI

struct CategoryTabButton: View {
    enum Size {
        case medium
        case small

        var font: Font {
            switch self {
            case .medium: .subheadline.weight(.medium)
            case .small: .caption.weight(.medium)
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .medium: 16
            case .small: 12
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .medium: 8
            case .small: 6
            }
        }
    }

    let label: String
    let isActive: Bool
    var isFocused: Bool = false
    var disabled: Bool = false
    var size: Size = .medium
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(size.font)
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, size.horizontalPadding)
                .padding(.vertical, size.verticalPadding)
                .background(backgroundColor, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(focusBorderColor, lineWidth: focusBorderWidth)
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
        #if os(tvOS)
        .tvFocusScale(isFocused)
        #endif
    }

    private var foregroundColor: Color {
        if isActive {
            return Color.white
        }
        #if os(tvOS)
        return Color.secondary
        #else
        return Color.primary
        #endif
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.accentColor
        }
        #if os(tvOS)
        return Color.white.opacity(isFocused ? 0.14 : 0.08)
        #else
        return AppTheme.secondaryFill
        #endif
    }

    private var focusBorderWidth: CGFloat {
        #if os(tvOS)
        isFocused ? 3 : 0
        #else
        0
        #endif
    }

    private var focusBorderColor: Color {
        #if os(tvOS)
        .white
        #else
        .clear
        #endif
    }
}

struct CategoryTabs: View {
    let primary: [CategoryDef]
    let secondary: [CategoryDef]
    let activeTypeId: Int?
    let activeParentId: Int?
    var pending: Bool = false
    let onSelect: (Int?) -> Void

    @FocusState private var focusedKey: String?

    private var showSecondary: Bool {
        !secondary.isEmpty && activeParentId != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tabRow(prefix: "p") {
                CategoryTabButton(
                    label: "全部",
                    isActive: activeTypeId == nil,
                    isFocused: focusedKey == focusKey(prefix: "p", id: nil),
                    disabled: pending
                ) { onSelect(nil) }
                .focused($focusedKey, equals: focusKey(prefix: "p", id: nil))

                ForEach(primary) { category in
                    CategoryTabButton(
                        label: category.label,
                        isActive: activeTypeId == category.typeId || activeParentId == category.typeId,
                        isFocused: focusedKey == focusKey(prefix: "p", id: category.typeId),
                        disabled: pending
                    ) { onSelect(category.typeId) }
                    .focused($focusedKey, equals: focusKey(prefix: "p", id: category.typeId))
                }
            }

            if showSecondary, let activeParentId {
                tabRow(prefix: "s") {
                    CategoryTabButton(
                        label: "全部",
                        isActive: activeTypeId == activeParentId,
                        isFocused: focusedKey == focusKey(prefix: "s", id: activeParentId),
                        disabled: pending,
                        size: .small
                    ) { onSelect(activeParentId) }
                    .focused($focusedKey, equals: focusKey(prefix: "s", id: activeParentId))

                    ForEach(secondary) { category in
                        CategoryTabButton(
                            label: category.label,
                            isActive: activeTypeId == category.typeId,
                            isFocused: focusedKey == focusKey(prefix: "s", id: category.typeId),
                            disabled: pending,
                            size: .small
                        ) { onSelect(category.typeId) }
                        .focused($focusedKey, equals: focusKey(prefix: "s", id: category.typeId))
                    }
                }
            }
        }
        #if os(tvOS)
        .padding(.horizontal, TVDesign.screenPadding)
        .padding(.vertical, 16)
        #else
        .padding(.horizontal)
        .padding(.vertical, 8)
        #endif
    }

    private func tabRow<Content: View>(prefix: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
        }
    }

    private func focusKey(prefix: String, id: Int?) -> String {
        "\(prefix)-\(id.map(String.init) ?? "all")"
    }
}
