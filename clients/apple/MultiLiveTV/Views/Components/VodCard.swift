import SwiftUI

struct VodCard: View {
    let item: VodItem
    var isFocused: Bool = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: URL(string: item.vodPic)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.gray.opacity(0.25)
                    }
                }
                .frame(height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isFocused ? Color.white : Color.clear, lineWidth: 4)
                )

                Text(item.vodName)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let remarks = item.vodRemarks {
                    Text(remarks)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
    }

    private var cardHeight: CGFloat {
        #if os(tvOS)
        280
        #else
        200
        #endif
    }
}
