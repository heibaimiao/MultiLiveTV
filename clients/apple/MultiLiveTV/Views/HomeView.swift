import SwiftUI
#if os(tvOS)
import TVServices
#endif

struct HomeView: View {
    @EnvironmentObject private var vod: VodService
    @EnvironmentObject private var deepLink: DeepLinkRouter
    @State private var categoryTree: CategoryTree
    @State private var selectedTypeId: Int?
    @State private var pool: [VodItem]
    @State private var displayCount: Int
    @State private var apiPage: Int
    @State private var pageCount: Int
    @State private var isLoading: Bool
    @State private var loadGeneration = 0
    @State private var errorMessage: String?
    @State private var selectedItem: VodItem?
    @State private var feedCache: HomeFeedCache
    @State private var loadTask: Task<Void, Never>?
    @State private var skipBootstrap: Bool
    @State private var categoryFocusRequest = 0
    @State private var catalogSourceId: Int?
    #if os(tvOS)
    @State private var showSearch = false
    @State private var returnFocusToCategories = false
    @Namespace private var homeFocus
    #endif
    @FocusState private var focusedId: String?

    init(launch: HomeLaunchPayload? = nil) {
        if let launch {
            _categoryTree = State(initialValue: launch.categoryTree)
            _selectedTypeId = State(initialValue: launch.selectedTypeId)
            _pool = State(initialValue: launch.snapshot.pool)
            _displayCount = State(initialValue: launch.snapshot.displayCount)
            _apiPage = State(initialValue: launch.snapshot.apiPage)
            _pageCount = State(initialValue: launch.snapshot.pageCount)
            _isLoading = State(initialValue: false)
            var cache = HomeFeedCache()
            cache.save(launch.snapshot, typeId: launch.selectedTypeId)
            _feedCache = State(initialValue: cache)
            _skipBootstrap = State(initialValue: true)
            _catalogSourceId = State(initialValue: launch.sourceId)
        } else {
            _categoryTree = State(initialValue: .empty)
            _selectedTypeId = State(initialValue: nil)
            _pool = State(initialValue: [])
            _displayCount = State(initialValue: 0)
            _apiPage = State(initialValue: 1)
            _pageCount = State(initialValue: 1)
            _isLoading = State(initialValue: true)
            _feedCache = State(initialValue: HomeFeedCache())
            _skipBootstrap = State(initialValue: false)
            _catalogSourceId = State(initialValue: nil)
        }
    }

    private var activeParentId: Int? {
        CategoryTreeBuilder.parentTypeId(tree: categoryTree, typeId: selectedTypeId)
    }

    private var secondaryCategories: [CategoryDef] {
        guard let parentId = activeParentId else { return [] }
        return (categoryTree.childrenByParent[parentId] ?? [])
            .filter { MacCMSCategoryService.isTypeVisible($0.label) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CategoryTabs(
                    primary: categoryTree.primary,
                    secondary: secondaryCategories,
                    activeTypeId: selectedTypeId,
                    activeParentId: activeParentId,
                    focusRequest: categoryFocusRequest,
                    focusedId: $focusedId,
                    onSearch: tvOpenSearch,
                    onSelect: selectCategory
                )
                #if os(tvOS)
                .prefersDefaultFocus(returnFocusToCategories, in: homeFocus)
                #endif
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .screenBackground()
            #if os(tvOS)
            .focusScope(homeFocus)
            .onChange(of: focusedId) { _, newValue in
                if newValue != nil, !CategoryFocus.isCategory(newValue) {
                    returnFocusToCategories = false
                }
            }
            #endif
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationDestination(item: $selectedItem) { item in
                DetailView(item: item)
                    .environmentObject(vod)
            }
            #if os(tvOS)
            .navigationDestination(isPresented: $showSearch) {
                SearchContent()
                    .environmentObject(vod)
            }
            #endif
            .task {
                guard !skipBootstrap else { return }
                await bootstrap()
            }
            .onAppear {
                consumeDeepLink()
                #if os(tvOS)
                if skipBootstrap {
                    persistTopShelf(from: pool)
                }
                #endif
            }
            .onChange(of: deepLink.pendingVod) { _, _ in consumeDeepLink() }
            #if os(tvOS)
            .onExitCommand(perform: shouldReturnToCategories ? jumpFocusToCategories : nil)
            #endif
        }
    }

    private var tvOpenSearch: (() -> Void)? {
        #if os(tvOS)
        { showSearch = true }
        #else
        nil
        #endif
    }

    #if os(tvOS)
    private var isMovieFocused: Bool {
        !CategoryFocus.isCategory(focusedId)
    }

    private var shouldReturnToCategories: Bool {
        selectedItem == nil && !showSearch && isMovieFocused
    }

    private func jumpFocusToCategories() {
        returnFocusToCategories = true
        let key = CategoryFocus.preferredKey(
            primary: categoryTree.primary,
            activeTypeId: selectedTypeId,
            activeParentId: activeParentId,
            showSecondary: !secondaryCategories.isEmpty && activeParentId != nil
        )
        categoryFocusRequest += 1
        Task { @MainActor in
            focusedId = key
        }
    }
    #endif

    private func consumeDeepLink() {
        guard let item = deepLink.pendingVod else { return }
        selectedItem = item
        deepLink.pendingVod = nil
    }

    private func selectCategory(_ typeId: Int?) {
        guard typeId != selectedTypeId || errorMessage != nil else { return }
        if pool.isEmpty == false {
            feedCache.save(currentSnapshot(), typeId: selectedTypeId)
        }
        selectedTypeId = typeId
        loadGeneration += 1
        loadTask?.cancel()
        errorMessage = nil
        if let snapshot = feedCache.snapshot(for: typeId) {
            applySnapshot(snapshot)
        } else {
            pool = []
            displayCount = 0
            apiPage = 1
            pageCount = 1
        }
        let generation = loadGeneration
        loadTask = Task { await fetchPage(page: 1, isFirst: true, generation: generation) }
    }

    @ViewBuilder
    private var content: some View {
        switch HomeFeed.contentPhase(isLoading: isLoading, errorMessage: errorMessage, poolIsEmpty: pool.isEmpty) {
        case .loading:
            PosterSkeletonGrid()
        case .error(let message):
            AppErrorView(message: message) {
                Task { await reload() }
            }
        case .empty:
            AppEmptyStateView(title: "暂无内容", subtitle: "请检查网络连接")
        case .content:
            #if os(tvOS)
            tvShelves
            #else
            ipadFeed
            #endif
        }
    }

    #if os(tvOS)
    private static let heroFocusID = "hero"

    private var heroItem: VodItem? {
        if let focusedId, focusedId != Self.heroFocusID,
           let item = pool.first(where: { $0.id == focusedId }) {
            return item
        }
        return pool.first
    }

    private var hotItems: [VodItem] {
        HomeFeed.hotItems(pool)
    }

    private var recentItems: [VodItem] {
        HomeFeed.recentItems(pool)
    }

    private var allItems: [VodItem] {
        HomeFeed.allItems(pool)
    }

    private var allRows: [[VodItem]] {
        HomeFeed.allRows(items: allItems, displayCount: displayCount)
    }

    private var canLoadMoreAll: Bool {
        HomeFeed.canLoadMoreAll(
            displayCount: displayCount,
            allLength: allItems.count,
            apiPage: apiPage,
            pageCount: pageCount
        )
    }

    private var tvShelves: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TVDesign.shelfSpacing) {
                if let heroItem {
                    Button {
                        selectedItem = heroItem
                    } label: {
                        HeroBanner(item: heroItem)
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .focused($focusedId, equals: Self.heroFocusID)
                    .overlay {
                        if focusedId == Self.heroFocusID {
                            RoundedRectangle(cornerRadius: AppTheme.posterRadius, style: .continuous)
                                .strokeBorder(Color.white, lineWidth: 4)
                                .padding(.horizontal, AppTheme.screenPadding)
                        }
                    }
                    .accessibilityLabel("播放\(heroItem.vodName)")
                }

                if !hotItems.isEmpty {
                    VodShelf(
                        title: "热门推荐",
                        items: hotItems,
                        focusedId: $focusedId,
                        onSelect: { selectedItem = $0 },
                        onLoadMore: recentItems.isEmpty && canLoadMoreAll
                            ? { Task { await tvLoadMore() } }
                            : nil
                    )
                }

                if !recentItems.isEmpty {
                    VodShelf(
                        title: "近期更新",
                        items: recentItems,
                        focusedId: $focusedId,
                        onSelect: { selectedItem = $0 },
                        onLoadMore: allItems.isEmpty && canLoadMoreAll
                            ? { Task { await tvLoadMore() } }
                            : nil
                    )
                }

                ForEach(Array(allRows.enumerated()), id: \.offset) { index, row in
                    VodShelf(
                        title: nil,
                        items: row,
                        focusedId: $focusedId,
                        onSelect: { selectedItem = $0 },
                        onLoadMore: index == allRows.count - 1
                            ? { Task { await tvLoadMore() } }
                            : nil
                    )
                }

                if canLoadMoreAll {
                    ProgressView()
                        .tint(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .id(HomeFeed.loadMoreFooterID(
                            displayCount: displayCount,
                            poolLength: allItems.count,
                            apiPage: apiPage
                        ))
                        .onAppear { Task { await tvLoadMore() } }
                }
            }
            .padding(.bottom, TVDesign.screenPadding)
        }
        .focusSection()
        .prefersDefaultFocus(!returnFocusToCategories, in: homeFocus)
    }
    #else
    private var ipadFeed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VodPosterGrid(items: visibleItems) { selectedItem = $0 }
                    .padding(.horizontal, AppTheme.screenPadding)

                loadMoreFooter
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }
    #endif

    #if os(tvOS)
    private func tvLoadMore() async {
        switch HomeFeed.nextAllLoadMore(
            displayCount: displayCount,
            allLength: allItems.count,
            apiPage: apiPage,
            pageCount: pageCount,
            isBusy: isLoading
        ) {
        case .reveal(let count):
            displayCount = count
        case .fetch(let page):
            await startFetch(page: page, isFirst: false, generation: loadGeneration)
        case .idle:
            break
        }
    }
    #else
    @ViewBuilder
    private var loadMoreFooter: some View {
        if canLoadMore {
            ProgressView()
                .tint(AppTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .id(HomeFeed.loadMoreFooterID(displayCount: displayCount, poolLength: pool.count, apiPage: apiPage))
                .onAppear { Task { await loadMore() } }
        }
    }

    private var visibleItems: [VodItem] {
        Array(pool.prefix(displayCount))
    }

    private var canLoadMore: Bool {
        HomeFeed.canLoadMore(displayCount: displayCount, poolLength: pool.count, apiPage: apiPage, pageCount: pageCount)
    }
    #endif

    private var knownChildTypeIds: [Int] {
        HomeLaunch.childTypeIds(tree: categoryTree, typeId: selectedTypeId)
    }

    private func currentSnapshot() -> HomeFeedSnapshot {
        HomeFeedSnapshot(pool: pool, displayCount: displayCount, apiPage: apiPage, pageCount: pageCount)
    }

    private func applySnapshot(_ snapshot: HomeFeedSnapshot) {
        pool = snapshot.pool
        displayCount = snapshot.displayCount
        apiPage = snapshot.apiPage
        pageCount = snapshot.pageCount
    }

    private func bootstrap() async {
        isLoading = true
        do {
            let payload = try await vod.loadHomeLaunch(tvDisplay: tvLaunchDisplay)
            applyLaunch(payload)
        } catch {
            errorMessage = RequestFailure.userFacingMessage(for: error)
            isLoading = false
        }
    }

    private var tvLaunchDisplay: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }

    private func applyLaunch(_ payload: HomeLaunchPayload) {
        categoryTree = payload.categoryTree
        selectedTypeId = payload.selectedTypeId
        catalogSourceId = payload.sourceId
        applySnapshot(payload.snapshot)
        feedCache.save(payload.snapshot, typeId: payload.selectedTypeId)
        errorMessage = nil
        isLoading = false
        #if os(tvOS)
        persistTopShelf(from: payload.snapshot.pool)
        #endif
    }

    private func reload() async {
        loadGeneration += 1
        loadTask?.cancel()
        let generation = loadGeneration
        pool = []
        displayCount = 0
        apiPage = 1
        pageCount = 1
        errorMessage = nil
        await startFetch(page: 1, isFirst: true, generation: generation)
    }

    #if !os(tvOS)
    private func loadMore() async {
        switch HomeFeed.nextLoadMore(
            displayCount: displayCount,
            poolLength: pool.count,
            apiPage: apiPage,
            pageCount: pageCount,
            isBusy: isLoading
        ) {
        case .reveal(let count):
            displayCount = count
        case .fetch(let page):
            await startFetch(page: page, isFirst: false, generation: loadGeneration)
        case .idle:
            break
        }
    }
    #endif

    private func startFetch(page: Int, isFirst: Bool, generation: Int) async {
        let task = Task { await fetchPage(page: page, isFirst: isFirst, generation: generation) }
        loadTask = task
        await task.value
    }

    private func fetchPage(page: Int, isFirst: Bool, generation: Int) async {
        let typeId = selectedTypeId
        let childTypeIds = knownChildTypeIds
        isLoading = true
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }
        do {
            let resp = try await vod.fetchList(
                page: page,
                typeId: typeId,
                sourceId: catalogSourceId,
                knownChildTypeIds: childTypeIds
            )
            guard !Task.isCancelled, generation == loadGeneration else { return }
            apiPage = page
            pageCount = max(resp.pagecount, 1)
            let incoming = CategoryMatch.filter(resp.list, selectedTypeId: typeId, tree: categoryTree)
            if isFirst {
                pool = HomeFeed.replaceFirstPage(pool: pool, incoming: incoming)
                #if os(tvOS)
                displayCount = HomeFeed.initialAllDisplayCount(allLength: HomeFeed.allItems(pool).count)
                persistTopShelf(from: pool)
                #else
                displayCount = HomeFeed.initialDisplayCount(poolLength: pool.count)
                #endif
            } else {
                pool = HomeFeed.mergeIntoPool(pool: pool, incoming: incoming, isFirstBatch: false)
                #if os(tvOS)
                displayCount = HomeFeed.nextAllDisplayCount(
                    current: displayCount,
                    allLength: HomeFeed.allItems(pool).count
                )
                #else
                displayCount = HomeFeed.nextDisplayCount(current: displayCount, poolLength: pool.count)
                #endif
            }
            feedCache.save(currentSnapshot(), typeId: typeId)
        } catch {
            guard !Task.isCancelled, generation == loadGeneration else { return }
            errorMessage = RequestFailure.userFacingMessage(for: error)
        }
    }

    #if os(tvOS)
    private func persistTopShelf(from items: [VodItem]) {
        TopShelfStore.save(items.map {
            TopShelfSnapshot(
                vodId: $0.vodId,
                sourceId: $0.resolvedSourceId,
                vodName: $0.vodName,
                vodPic: $0.vodPic
            )
        })
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
    #endif
}
