import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var vod: VodService
    @State private var categoryTree = CategoryTree.empty
    @State private var selectedTypeId: Int?
    @State private var pool: [VodItem] = []
    @State private var displayCount = 0
    @State private var apiPage = 1
    @State private var pageCount = 1
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedItem: VodItem?
    @FocusState private var focusedId: String?

    private var activeParentId: Int? {
        CategoryTreeBuilder.parentTypeId(tree: categoryTree, typeId: selectedTypeId)
    }

    private var secondaryCategories: [CategoryDef] {
        guard let parentId = activeParentId else { return [] }
        return categoryTree.childrenByParent[parentId] ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CategoryTabs(
                    primary: categoryTree.primary,
                    secondary: secondaryCategories,
                    activeTypeId: selectedTypeId,
                    activeParentId: activeParentId,
                    pending: isLoading,
                    onSelect: selectCategory
                )
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .screenBackground()
            .navigationTitle(selectedTypeId == nil ? "MultiLiveTV" : CategoryTreeBuilder.label(tree: categoryTree, typeId: selectedTypeId))
            .navigationDestination(item: $selectedItem) { item in
                DetailView(item: item)
                    .environmentObject(vod)
            }
            .task { await bootstrap() }
        }
    }

    private func selectCategory(_ typeId: Int?) {
        guard typeId != selectedTypeId || errorMessage != nil else { return }
        selectedTypeId = typeId
        Task { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && pool.isEmpty {
            AppLoadingView()
        } else if let errorMessage, pool.isEmpty {
            AppErrorView(message: errorMessage) {
                Task { await reload() }
            }
        } else if pool.isEmpty {
            AppEmptyStateView(title: "暂无内容", subtitle: "请检查网络连接")
        } else {
            #if os(tvOS)
            tvShelves
            #else
            ipadGrid
            #endif
        }
    }

    #if os(tvOS)
    private var heroItem: VodItem? {
        if let focusedId, let item = pool.first(where: { $0.id == focusedId }) {
            return item
        }
        return pool.first
    }

    private var shelves: [(title: String, items: [VodItem])] {
        let items = visibleItems
        let chunkSize = 8
        var result: [(String, [VodItem])] = []
        for (index, start) in stride(from: 0, to: items.count, by: chunkSize).enumerated() {
            let end = min(start + chunkSize, items.count)
            let chunk = Array(items[start..<end])
            let title = index == 0 ? "热门推荐" : "更多精彩内容"
            result.append((title, chunk))
        }
        return result
    }

    private var tvShelves: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVDesign.shelfSpacing) {
                if let heroItem {
                    HeroBanner(item: heroItem)
                        .padding(.top, 8)
                }

                ForEach(Array(shelves.enumerated()), id: \.offset) { _, shelf in
                    VodShelf(
                        title: shelf.title,
                        items: shelf.items,
                        focusedId: $focusedId,
                        onSelect: { selectedItem = $0 }
                    )
                }

                if canLoadMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .onAppear { Task { await loadMore() } }
                }
            }
            .padding(.bottom, TVDesign.screenPadding)
        }
    }
    #else
    private var ipadGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16, alignment: .top)],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(visibleItems) { item in
                    VodCard(item: item) { selectedItem = item }
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding()

            if canLoadMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .onAppear { Task { await loadMore() } }
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
            let types = try await vod.fetchTypes()
            categoryTree = CategoryTreeBuilder.build(from: types.categories)
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
        errorMessage = nil
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
            let resp = try await vod.fetchList(page: apiPage, typeId: selectedTypeId)
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
}
