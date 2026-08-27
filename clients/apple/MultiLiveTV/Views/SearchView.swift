import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var vod: VodService
    @State private var keyword = ""
    @State private var results: [VodItem] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var errorMessage: String?
    @State private var selectedItem: VodItem?
    @FocusState private var focusedId: String?
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                searchContent
            }
            .screenBackground()
            .navigationTitle("搜索")
            .navigationDestination(item: $selectedItem) { item in
                DetailView(item: item)
                    .environmentObject(vod)
            }
        }
    }

    @ViewBuilder
    private var searchBar: some View {
        #if os(tvOS)
        HStack(spacing: 24) {
            HStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                TextField("搜索影片", text: $keyword)
                    .font(.title3)
                    .focused($searchFieldFocused)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(searchFieldFocused ? Color.white : Color.clear, lineWidth: 3)
            }

            Button("搜索") { Task { await search() } }
                .buttonStyle(.borderedProminent)
                .disabled(isSearching || keyword.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, TVDesign.screenPadding)
        .padding(.vertical, 24)
        #else
        HStack {
            TextField("搜索影片", text: $keyword)
                .textFieldStyle(.roundedBorder)
            Button("搜索") { Task { await search() } }
                .buttonStyle(.borderedProminent)
                .disabled(isSearching)
        }
        .padding()
        #endif
    }

    @ViewBuilder
    private var searchContent: some View {
        if isSearching {
            AppLoadingView(message: "搜索中…")
        } else if let errorMessage {
            AppErrorView(message: errorMessage) {
                Task { await search() }
            }
        } else if hasSearched && results.isEmpty {
            AppEmptyStateView(title: "未找到结果", subtitle: "试试其他关键词")
        } else {
            #if os(tvOS)
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: TVDesign.cardWidth), spacing: TVDesign.cardSpacing)],
                    spacing: TVDesign.cardSpacing
                ) {
                    ForEach(results) { item in
                        VodCard(item: item, isFocused: focusedId == item.id, layout: .grid) {
                            selectedItem = item
                        }
                        .focused($focusedId, equals: item.id)
                    }
                }
                .padding(TVDesign.screenPadding)
            }
            #else
            List(results) { item in
                Button(item.vodName) { selectedItem = item }
            }
            #endif
        }
    }

    private func search() async {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        defer {
            isSearching = false
            hasSearched = true
        }
        do {
            results = try await vod.search(trimmed)
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
    }
}
