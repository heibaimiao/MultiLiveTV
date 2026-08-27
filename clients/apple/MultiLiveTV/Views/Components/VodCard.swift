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

                if layout == .grid {
                    Text(item.vodName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)

                    if let typeName = item.typeName {
                        Text(typeName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            #if os(tvOS)
            .frame(width: TVDesign.cardWidth)
            #endif
        }
        #if os(tvOS)
        .buttonStyle(.plain)
        .tvFocusScale(isFocused)
        #else
        .buttonStyle(.plain)
        #endif
    }

    @ViewBuilder
    private var poster: some View {
        Group {
            #if os(tvOS)
            AsyncImage(url: URL(string: item.vodPic)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    AppTheme.tertiaryFill
                }
            }
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(isFocused ? Color.white : Color.clear, lineWidth: 4)
        }
        .overlay(alignment: .bottomLeading) {
            if layout == .shelf {
                shelfTitleOverlay
            }
        }
    }

    @ViewBuilder
    private var shelfTitleOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.vodName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.white)
            if let remarks = item.displayRemarks {
                Text(remarks)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var cornerRadius: CGFloat {
        #if os(tvOS)
        TVDesign.cornerRadius
        #else
        12
        #endif
    }

    #if os(iOS)
    private static let posterAspectRatio: CGFloat = 2 / 3
    #endif
}
