import SwiftUI

struct VodCard: View {
    enum Layout {
        case grid
        case shelf
    }

    let item: VodItem
    var isFocused: Bool = false
    var layout: Layout = .grid
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                poster
                caption
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            #if os(tvOS)
            .frame(width: TVDesign.cardWidth)
            #endif
        }
        #if os(tvOS)
        .tvFocusChrome(isFocused)
        #else
        .buttonStyle(.plain)
        #endif
    }

    @ViewBuilder
    private var poster: some View {
        Group {
            #if os(tvOS)
            VodPosterView(
                sourceId: item.resolvedSourceId,
                vodId: item.vodId,
                initialURL: item.vodPic,
                cornerRadius: cornerRadius,
                showRemarks: item.displayRemarks
            )
            .frame(width: TVDesign.cardWidth, height: TVDesign.cardHeight)
            #else
            Color.clear
                .aspectRatio(Self.posterAspectRatio, contentMode: .fit)
                .overlay {
                    VodPosterView(
                        sourceId: item.resolvedSourceId,
                        vodId: item.vodId,
                        initialURL: item.vodPic,
                        cornerRadius: cornerRadius,
                        showRemarks: item.displayRemarks
                    )
                }
            #endif
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(isFocused ? Color.white.opacity(0.95) : Color.clear, lineWidth: 3)
        }
        .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.vodName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isFocused ? AppTheme.textPrimary : AppTheme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: layout == .grid ? 40 : 0, alignment: .topLeading)

            if layout == .grid, let genre = item.displayGenreLine {
                Text(genre)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }
        }
        .opacity(isFocused || layout == .grid ? 1 : 0.9)
    }

    private var cornerRadius: CGFloat {
        AppTheme.posterRadius
    }

    #if os(iOS)
    private static let posterAspectRatio: CGFloat = 2 / 3
    #endif
}
