import SwiftUI

#if os(tvOS)
struct VodShelf: View {
    var title: String? = nil
    let items: [VodItem]
    var focusedId: FocusState<String?>.Binding
    let onSelect: (VodItem) -> Void
    var onLoadMore: (() -> Void)? = nil

    @State private var loadMoreToken = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.leading, TVDesign.screenPadding)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TVDesign.cardSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        VodCard(
                            item: item,
                            isFocused: focusedId.wrappedValue == item.id,
                            layout: .shelf
                        ) {
                            onSelect(item)
                        }
                        .focused(focusedId, equals: item.id)
                        .onAppear { maybeLoadMore(index: index) }
                        .onChange(of: focusedId.wrappedValue) { _, newValue in
                            if newValue == item.id {
                                maybeLoadMore(index: index)
                            }
                        }
                    }
                }
                .padding(.horizontal, TVDesign.screenPadding)
                .padding(.vertical, 36)
            }
            .scrollClipDisabled()
        }
        .onChange(of: items.map(\.vodId)) { _, _ in
            loadMoreToken = ""
        }
    }

    private func maybeLoadMore(index: Int) {
        guard onLoadMore != nil else { return }
        guard HomeFeed.shouldPrefetchMore(index: index, itemCount: items.count) else { return }
        let token = "\(items.count)-\(items.last?.vodId ?? "")"
        guard token != loadMoreToken else { return }
        loadMoreToken = token
        onLoadMore?()
    }
}
#endif
