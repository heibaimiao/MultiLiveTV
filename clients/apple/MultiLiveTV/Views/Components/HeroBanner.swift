import SwiftUI

#if os(tvOS)
struct HeroBanner: View {
    let item: VodItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: item.vodPic)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    LinearGradient(
                        colors: [Color(white: 0.15), Color(white: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(height: TVDesign.heroHeight)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: TVDesign.heroHeight)

            VStack(alignment: .leading, spacing: 12) {
                if let typeName = item.typeName {
                    Text(typeName.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .tracking(1.2)
                }

                Text(item.vodName)
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let remarks = item.displayRemarks {
                    Text(remarks)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.75))
                }

                if let blurb = item.displayBlurb {
                    Text(blurb)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                        .frame(maxWidth: 900, alignment: .leading)
                }
            }
            .padding(.horizontal, TVDesign.screenPadding)
            .padding(.bottom, 36)
        }
        .frame(height: TVDesign.heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: TVDesign.cornerRadius))
        .padding(.horizontal, TVDesign.screenPadding)
        .animation(.easeInOut(duration: 0.3), value: item.id)
    }
}
#endif
