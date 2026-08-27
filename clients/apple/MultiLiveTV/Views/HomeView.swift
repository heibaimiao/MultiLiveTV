import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var api: APIClient
    @State private var categories: [CategoryDef] = []
    @State private var selectedTypeId: Int?
    @State private var pool: [VodItem] = []
    @State private var displayCount = 0
    @State private var apiPage = 1
    @State private var pageCount = 1
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedItem: VodItem?
    @State private var detail: DetailResponse?
    @FocusState private var focusedId: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryBar
                content
            }
            .navigationTitle("MultiLiveTV")
            .task { await bootstrap() }
            .sheet(item: $selectedItem) { item in
                DetailView(item: item, detail: detail, onAppear: {
                    Task { await loadDetail(for: item) }
                })
            }
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                categoryChip(label: "全部", typeId: nil)
                ForEach(categories) { cat in
                    categoryChip(label: cat.label, typeId: cat.typeId)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func categoryChip(label: String, typeId: Int?) -> some View {
        let selected = selectedTypeId == typeId
        return Button(label) {
            selectedTypeId = typeId
            Task { await reload() }
        }
        .buttonStyle(.bordered)
        .tint(selected ? .accentColor : .secondary)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && pool.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            Text(errorMessage).foregroundStyle(.red).padding()
        } else {
            #if os(tvOS)
            tvGrid
            #else
            ipadGrid
            #endif
        }
    }

    #if os(tvOS)
    private var tvGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 32)], spacing: 32) {
                ForEach(visibleItems) { item in
                    VodCard(item: item, isFocused: focusedId == item.id) {
                        selectedItem = item
                    }
                    .focused($focusedId, equals: item.id)
                }
            }
            .padding(48)
            if canLoadMore {
                ProgressView().onAppear { Task { await loadMore() } }
            }
        }
    }
    #else
    private var ipadGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                ForEach(visibleItems) { item in
                    VodCard(item: item) { selectedItem = item }
                }
            }
            .padding()
            if canLoadMore {
                ProgressView().frame(maxWidth: .infinity).onAppear { Task { await loadMore() } }
            }
        }
    }
    #endif

    private var visibleItems: [VodItem] {
        Array(pool.prefix(displayCount))
    }

    private var canLoadMore: Bool {
        HomeFeed.canLoadMore(displayCount: displayCount, poolLength: pool.count, apiPage: apiPage, pageCount: pageCount)
    }

    private func bootstrap() async {
        do {
            let types = try await api.fetchTypes()
            categories = types.categories
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() async {
        pool = []
        displayCount = 0
        apiPage = 1
        pageCount = 1
        await fetchPage(isFirst: true)
    }

    private func loadMore() async {
        if displayCount < pool.count {
            displayCount = HomeFeed.nextDisplayCount(current: displayCount, poolLength: pool.count)
            return
        }
        guard apiPage < pageCount else { return }
        apiPage += 1
        await fetchPage(isFirst: false)
    }

    private func fetchPage(isFirst: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await api.fetchList(page: apiPage, typeId: selectedTypeId)
            pageCount = max(resp.pagecount, 1)
            pool = HomeFeed.mergeIntoPool(pool: pool, incoming: resp.list, isFirstBatch: isFirst)
            if isFirst {
                displayCount = HomeFeed.initialDisplayCount(poolLength: pool.count)
            } else {
                displayCount = HomeFeed.nextDisplayCount(current: displayCount, poolLength: pool.count)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDetail(for item: VodItem) async {
        do {
            detail = try await api.detail(sourceId: item.resolvedSourceId, vodId: item.vodId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
