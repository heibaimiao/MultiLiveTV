import SwiftUI

#if os(tvOS)
struct VodShelf: View {
    let title: String
    let items: [VodItem]
    var focusedId: FocusState<String?>.Binding
    let onSelect: (VodItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, TVDesign.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TVDesign.cardSpacing) {
                    ForEach(items) { item in
                        VodCard(
                            item: item,
                            isFocused: focusedId.wrappedValue == item.id,
                            layout: .shelf
                        ) {
                            onSelect(item)
                        }
                        .focused(focusedId, equals: item.id)
                    }
                }
                .padding(.horizontal, TVDesign.screenPadding)
                .padding(.vertical, 8)
            }
        }
    }
}
#endif
