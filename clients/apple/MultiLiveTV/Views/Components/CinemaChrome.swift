import SwiftUI

struct CinemaBackdrop: View {
    let urlString: String
    var height: CGFloat
    var blur: Bool = true

    var body: some View {
        ZStack {
            AppTheme.elevated

            RemoteImageView(url: RemoteMediaURL.parse(urlString)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: blur ? 22 : 0)
                        .scaleEffect(blur ? 1.14 : 1)
                default:
                    EmptyView()
                }
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.18), location: 0),
                    .init(color: AppTheme.screenBackground.opacity(0.45), location: 0.42),
                    .init(color: AppTheme.screenBackground.opacity(0.92), location: 0.82),
                    .init(color: AppTheme.screenBackground, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [AppTheme.screenBackground.opacity(0.72), .clear],
                startPoint: .leading,
                endPoint: .center
            )
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

struct MetaChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.secondaryFill, in: Capsule())
    }
}

struct CinemaActionButton: View {
    enum Kind {
        case prominent
        case secondary
    }

    let title: String
    let systemImage: String
    var kind: Kind = .prominent
    var isFocused: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
        }
        #if os(tvOS)
        .tvFocusChrome(isFocused)
        #else
        .buttonStyle(.plain)
        #endif
    }

    private var usesSolidFill: Bool {
        kind == .prominent || isFocused
    }

    private var foreground: Color {
        usesSolidFill ? .black : AppTheme.textPrimary
    }

    private var background: Color {
        if usesSolidFill {
            return .white
        }
        return AppTheme.secondaryFill
    }
}

struct VodPosterGrid: View {
    let items: [VodItem]
    var focusedId: FocusState<String?>.Binding? = nil
    let onSelect: (VodItem) -> Void

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            ForEach(items) { item in
                VodCard(
                    item: item,
                    isFocused: focusedId?.wrappedValue == item.id,
                    layout: .grid
                ) {
                    onSelect(item)
                }
                .modifier(OptionalCardFocus(binding: focusedId, id: item.id))
            }
        }
    }

    private var spacing: CGFloat {
        #if os(tvOS)
        TVDesign.cardSpacing
        #else
        AppTheme.gridSpacing
        #endif
    }

    private var columns: [GridItem] {
        #if os(tvOS)
        [GridItem(.adaptive(minimum: TVDesign.cardWidth), spacing: TVDesign.cardSpacing, alignment: .top)]
        #else
        [GridItem(.adaptive(minimum: AppTheme.cardMinWidth, maximum: 220), spacing: AppTheme.gridSpacing, alignment: .top)]
        #endif
    }
}

private struct OptionalCardFocus: ViewModifier {
    var binding: FocusState<String?>.Binding?
    let id: String

    func body(content: Content) -> some View {
        if let binding {
            content.focused(binding, equals: id)
        } else {
            content
        }
    }
}

struct PosterSkeletonGrid: View {
    var count: Int = 12

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.gridSpacing) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: AppTheme.posterRadius, style: .continuous)
                    .fill(AppTheme.tertiaryFill)
                    .aspectRatio(2 / 3, contentMode: .fit)
            }
        }
        .padding(AppTheme.screenPadding)
        .redacted(reason: .placeholder)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: AppTheme.cardMinWidth), spacing: AppTheme.gridSpacing, alignment: .top)]
    }
}
