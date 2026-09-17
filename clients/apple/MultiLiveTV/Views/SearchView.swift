import SwiftUI

struct SearchView: View {
    var body: some View {
        NavigationStack {
            SearchContent()
        }
    }
}

struct SearchContent: View {
    @EnvironmentObject private var vod: VodService
    @EnvironmentObject private var downloads: DownloadManager
    @State private var keyword = ""
    @State private var results: [VodItem] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var errorMessage: String?
    @State private var selectedItem: VodItem?
    @State private var searchGeneration = 0
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focusedId: String?
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            resultsPane
        }
        .screenBackground()
        .navigationTitle("搜索")
        .navigationDestination(item: $selectedItem) { item in
            DetailView(item: item)
                .environmentObject(vod)
                .environmentObject(downloads)
        }
        .onAppear {
            searchFieldFocused = true
        }
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(AppTheme.textTertiary)

                TextField("搜索影片", text: $keyword)
                    .font(.title3)
                    .foregroundStyle(AppTheme.textPrimary)
                    .focused($searchFieldFocused)
                    .onSubmit { startSearch() }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                    .strokeBorder(searchFieldFocused ? Color.white : Color.white.opacity(0.08), lineWidth: searchFieldFocused ? 3 : 1)
            }

            Button("搜索") { startSearch() }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(isSearching || keyword.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, AppTheme.screenPadding)
        .padding(.vertical, 18)
        .tvFocusSection()
        #if os(tvOS)
        .defaultFocus($searchFieldFocused, true)
        #endif
    }

    @ViewBuilder
    private var resultsPane: some View {
        if isSearching && results.isEmpty && errorMessage == nil {
            PosterSkeletonGrid(count: 10)
        } else if let errorMessage {
            AppErrorView(message: errorMessage) {
                startSearch()
            }
            .iPadFillScrollRefreshable { startSearch(); await searchTask?.value }
        } else if hasSearched && results.isEmpty {
            AppEmptyStateView(title: "未找到结果", subtitle: "试试其他关键词", systemImage: "magnifyingglass")
                .iPadFillScrollRefreshable { startSearch(); await searchTask?.value }
        } else if results.isEmpty {
            AppEmptyStateView(title: "搜索影片", subtitle: "输入片名、演员或关键词", systemImage: "magnifyingglass")
        } else {
            ScrollView {
                VodPosterGrid(items: results, focusedId: $focusedId) { selectedItem = $0 }
                    .padding(AppTheme.screenPadding)
            }
            .iPadRefreshable { startSearch(); await searchTask?.value }
            .tvFocusSection()
        }
    }

    private func startSearch() {
        searchTask?.cancel()
        searchTask = Task { await search() }
    }

    private func search() async {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        errorMessage = nil
        defer {
            if RequestGeneration.shouldApply(eventGeneration: generation, currentGeneration: searchGeneration) {
                isSearching = false
            }
        }
        do {
            let found = try await vod.search(trimmed)
            guard RequestGeneration.shouldApply(eventGeneration: generation, currentGeneration: searchGeneration) else {
                return
            }
            results = found
            errorMessage = nil
            hasSearched = true
        } catch {
            guard RequestGeneration.shouldApply(eventGeneration: generation, currentGeneration: searchGeneration) else {
                return
            }
            if RequestGeneration.isCancellation(error) {
                return
            }
            errorMessage = RequestFailure.userFacingMessage(for: error)
            results = []
            hasSearched = true
        }
    }
}
