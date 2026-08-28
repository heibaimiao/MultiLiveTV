import SwiftUI

struct HeroBanner: View {
    let item: VodItem
    var compact: Bool = false

    private var height: CGFloat {
        #if os(tvOS)
        TVDesign.heroHeight
        #else
        compact ? 240 : 280
        #endif
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CinemaBackdrop(urlString: item.vodPic, height: height)

            HStack(alignment: .bottom, spacing: 28) {
                poster

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        if let typeName = item.typeName, !typeName.isEmpty {
                            MetaChip(text: typeName)
                        }
                        if let remarks = item.displayRemarks {
                            MetaChip(text: remarks)
                        }
                    }

                    Text(item.vodName)
                        .font(titleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)

                    if let blurb = item.displayBlurb {
                        Text(blurb)
                            .font(blurbFont)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(compact ? 2 : 3)
                            .frame(maxWidth: 760, alignment: .leading)
                    }
                }
                .padding(.bottom, compact ? 16 : 28)
            }
            .padding(.horizontal, AppTheme.screenPadding)
            .padding(.bottom, compact ? 12 : 20)
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.35), value: item.id)
    }

    @ViewBuilder
    private var poster: some View {
        VodPosterView(
            sourceId: item.resolvedSourceId,
            vodId: item.vodId,
            initialURL: item.vodPic,
            cornerRadius: AppTheme.posterRadius,
            showRemarks: nil
        )
        .frame(width: posterWidth, height: posterHeight)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.posterRadius, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        #if os(iOS)
        .padding(.bottom, 8)
        #endif
    }

    private var titleFont: Font {
        #if os(tvOS)
        .system(size: 48, weight: .bold)
        #else
        .system(size: compact ? 28 : 34, weight: .bold)
        #endif
    }

    private var blurbFont: Font {
        #if os(tvOS)
        .title3
        #else
        .subheadline
        #endif
    }

    private var posterWidth: CGFloat {
        #if os(tvOS)
        210
        #else
        compact ? 96 : 120
        #endif
    }

    private var posterHeight: CGFloat {
        posterWidth * 1.5
    }
}
