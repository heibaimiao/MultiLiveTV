import Foundation

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fail("\(message): expected \(expected), got \(actual)")
    }
}

func vod(_ id: String, _ name: String, time: Int = 0, typeName: String? = nil, vodClass: String? = nil) -> VodItem {
    VodItem(vodId: id, vodName: name, vodPic: "", typeName: typeName, vodClass: vodClass, vodTime: time)
}

func raw(_ id: String, _ name: String) -> VodItemRaw {
    VodItemRaw(
        vodId: id,
        vodName: name,
        vodPic: "",
        vodRemarks: "",
        vodYear: "",
        vodArea: "",
        vodClass: "",
        vodBlurb: "",
        vodContent: "",
        vodPlayFrom: "",
        vodPlayURL: "",
        typeId: 0,
        typeName: "",
        vodTime: 0
    )
}

func source(_ id: Int, _ name: String) -> Source {
    Source(id: id, name: name, url: "https://example.com/\(id)/", flag: 0, jxUrl: nil, vipOnly: false)
}

func testMergeIntoPoolPreservesIncomingOrder() {
    let incoming = (1...5).map { vod("id-\($0)", "片名\($0)") }
    let names = HomeFeed.mergeIntoPool(pool: [], incoming: incoming, isFirstBatch: true).map(\.vodName)
    assertEqual(names, incoming.map(\.vodName), "first batch should keep API order")
}

func testMergeIntoPoolKeepsFirstSeenPositionWhenTitleDuplicates() {
    let incoming = [
        vod("1", "同名"),
        vod("2", "乙"),
        vod("3", "同名"),
    ]
    let merged = HomeFeed.mergeIntoPool(pool: [], incoming: incoming, isFirstBatch: true)
    assertEqual(merged.map(\.vodName), ["同名", "乙"], "duplicate titles should collapse in first-seen order")
    assertEqual(merged[0].vodId, "3", "later duplicate should replace content at original position")
}

func testMergeIntoPoolAppendsNewcomersAfterExistingPool() {
    let pool = [vod("1", "甲"), vod("2", "乙")]
    let incoming = [vod("3", "丙"), vod("2-new", "乙"), vod("4", "丁")]
    let merged = HomeFeed.mergeIntoPool(pool: pool, incoming: incoming, isFirstBatch: false)
    assertEqual(merged.map(\.vodName), ["甲", "乙", "丙", "丁"], "pool order should stay, newcomers append in incoming order")
    assertEqual(merged[1].vodId, "2", "existing pool items should not be reordered or replaced by later pages")
}

func testContentPhasePrefersLoadingOverEmpty() {
    let phase = HomeFeed.contentPhase(isLoading: true, errorMessage: nil, poolIsEmpty: true)
    assertEqual(phase, .loading, "bootstrap with empty pool should show loading, not empty state")
}

func testContentPhaseEmptyOnlyWhenIdle() {
    let phase = HomeFeed.contentPhase(isLoading: false, errorMessage: nil, poolIsEmpty: true)
    assertEqual(phase, .empty, "idle empty pool should show empty state")
}

func testCategorySwitchShowsLoadingWhenCacheMisses() {
    let plan = HomeFeed.categorySwitchPlan(hasCachedSnapshot: false)
    assertEqual(plan.showLoading, true, "uncached category switch must not flash the empty state")
    assertEqual(plan.preserveLoadedPages, false, "a new category should replace the pool, not keep another category's pages")
}

func testCategorySwitchPreservesPagesWhenCacheHits() {
    let plan = HomeFeed.categorySwitchPlan(hasCachedSnapshot: true)
    assertEqual(plan.showLoading, false, "cached category should keep showing posters while page 1 refreshes")
    assertEqual(plan.preserveLoadedPages, true, "cached category refresh must not drop already loaded pages")
}

func testPullRefreshKeepsPostersWhenFeedHasContent() {
    let plan = HomeFeed.pullRefreshPlan(hasContent: true)
    assertEqual(plan.showLoading, false, "iPad pull-to-refresh must not replace posters with the full-screen skeleton")
    assertEqual(plan.preserveLoadedPages, true, "pull-to-refresh should update page 1 in place and keep already loaded pages")
}

func testPullRefreshShowsLoadingWhenFeedIsEmpty() {
    let plan = HomeFeed.pullRefreshPlan(hasContent: false)
    assertEqual(plan.showLoading, true, "empty or error feed can show loading while pull-to-refresh retries")
    assertEqual(plan.preserveLoadedPages, false, "an empty feed has no extra pages to preserve")
}

func testRefreshFirstPageKeepsAlreadyLoadedPages() {
    let pool = [
        vod("1", "首页甲"),
        vod("2", "首页乙"),
        vod("3", "第二页丙"),
        vod("4", "第二页丁"),
    ]
    let incoming = [vod("1b", "首页甲"), vod("5", "新片戊")]
    let refreshed = HomeFeed.refreshFirstPage(pool: pool, incoming: incoming)
    assertEqual(refreshed.map(\.vodId), ["1b", "5", "2", "3", "4"], "page 1 should update in place and keep titles that are not in the new first page")
    assertEqual(HomeFeed.clampedDisplayCount(current: 12, poolLength: refreshed.count), 5, "displayCount should clamp to the new pool, not reset to the first row")
}

func testLoadMoreRevealsBeforeFetching() {
    let action = HomeFeed.nextLoadMore(
        displayCount: 30,
        poolLength: 50,
        apiPage: 1,
        pageCount: 3,
        isBusy: false
    )
    assertEqual(action, .reveal(displayCount: 50), "should reveal pooled items before requesting next API page")
}

func testLoadMoreFetchesNextPageWhenPoolExhausted() {
    let action = HomeFeed.nextLoadMore(
        displayCount: 50,
        poolLength: 50,
        apiPage: 1,
        pageCount: 3,
        isBusy: false
    )
    assertEqual(action, .fetch(page: 2), "should fetch next API page after pooled items are visible")
}

func testLoadMoreIdleWhileBusy() {
    let action = HomeFeed.nextLoadMore(
        displayCount: 50,
        poolLength: 50,
        apiPage: 1,
        pageCount: 3,
        isBusy: true
    )
    assertEqual(action, .idle, "should not start another page load while a request is in flight")
}

func testShouldRetriggerLoadMoreFooterWhenDisplayCountChanges() {
    let first = HomeFeed.loadMoreFooterID(displayCount: 30, poolLength: 50, apiPage: 1)
    let afterReveal = HomeFeed.loadMoreFooterID(displayCount: 50, poolLength: 50, apiPage: 1)
    if first == afterReveal {
        fail("footer identity must change after revealing more items so onAppear can fire again")
    }
}

func testHomeFeedCacheRestoresSnapshotByTypeId() {
    var cache = HomeFeedCache()
    let movies = HomeFeedSnapshot(
        pool: [vod("m1", "电影甲"), vod("m2", "电影乙")],
        displayCount: 2,
        apiPage: 1,
        pageCount: 4
    )
    cache.save(movies, typeId: 20)
    cache.save(
        HomeFeedSnapshot(pool: [vod("a1", "动作")], displayCount: 1, apiPage: 1, pageCount: 2),
        typeId: 21
    )

    let restored = cache.snapshot(for: 20)
    assertEqual(restored?.pool.map(\.vodId) ?? [], ["m1", "m2"], "cache hit should restore the matching typeId pool")
    assertEqual(restored?.displayCount ?? 0, 2, "cache hit should restore displayCount")
    assertEqual(restored?.pageCount ?? 0, 4, "cache hit should restore pageCount")
}

func testHomeFeedCacheTreatsNilTypeIdAsAllCategory() {
    var cache = HomeFeedCache()
    cache.save(
        HomeFeedSnapshot(pool: [vod("all", "首页")], displayCount: 1, apiPage: 1, pageCount: 1),
        typeId: nil
    )
    cache.save(
        HomeFeedSnapshot(pool: [vod("m1", "电影")], displayCount: 1, apiPage: 1, pageCount: 1),
        typeId: 20
    )

    let all = cache.snapshot(for: nil)
    assertEqual(all?.pool.map(\.vodId) ?? [], ["all"], "nil typeId should be the 全部 bucket, not collide with a numeric typeId")
    if cache.snapshot(for: 99) != nil {
        fail("unknown typeId should be a cache miss")
    }
}

func testReplaceFirstPageDropsLeftoverItemsFromPreviousCategory() {
    let leftover = [vod("old-1", "首页片"), vod("old-2", "另一部")]
    let incoming = [vod("new-1", "动作片甲"), vod("new-2", "动作片乙")]
    let replaced = HomeFeed.replaceFirstPage(pool: leftover, incoming: incoming)
    assertEqual(replaced.map(\.vodId), ["new-1", "new-2"], "first page of a category must replace leftover posters, not merge them")
}

func testReplaceFirstPageDedupesAndCapsAtFetchSize() {
    var incoming = (1...60).map { vod("id-\($0)", "片名\($0)") }
    incoming.append(vod("id-1-dup", "片名1"))
    let replaced = HomeFeed.replaceFirstPage(pool: [vod("stale", "旧分类")], incoming: incoming)
    assertEqual(replaced.count, HomeFeed.fetchSize, "first page should cap at fetchSize")
    assertEqual(replaced.first?.vodId, "id-1-dup", "duplicate titles on first page should keep last-seen content")
    assertEqual(replaced.map(\.vodName).contains("旧分类"), false, "stale previous-category titles must not remain")
}

func testContentPhaseKeepsContentWhileRefreshingCachedPool() {
    let phase = HomeFeed.contentPhase(isLoading: true, errorMessage: nil, poolIsEmpty: false)
    assertEqual(phase, .content, "cache restore plus background refresh must not flash the full-screen loader")
}

func testHotRecentSplitUsesFirstSixAsHotAndSortsRecentByTime() {
    let pool = (1...20).map { vod("\($0)", "片\($0)", time: $0) }
    let hot = HomeFeed.hotItems(pool)
    let recent = HomeFeed.recentItems(pool)
    let all = HomeFeed.allItems(pool)
    assertEqual(hot.map(\.vodId), (1...6).map(String.init), "hot shelf should keep the first 6 items in API order")
    assertEqual(recent.map(\.vodId), (15...20).reversed().map(String.init), "recent shelf should be the newest 6 leftovers")
    assertEqual(all.map(\.vodId), (7...14).reversed().map(String.init), "all section should continue newest-first after recent")
}

func testRecentCapsAtSixAndAllKeepsNewestFirst() {
    let pool = (1...50).map { vod("\($0)", "片\($0)", time: $0) }
    let recent = HomeFeed.recentItems(pool)
    let all = HomeFeed.allItems(pool)
    assertEqual(recent.map(\.vodId), (45...50).reversed().map(String.init), "recent should keep only the newest 6 leftovers")
    assertEqual(all.map(\.vodId), (7...44).reversed().map(String.init), "all should be the remaining leftovers, newest vodTime first")
    assertEqual(all.count, 38, "50-item pool should leave 38 items for the all section")
}

func testAllWindowRevealsSixAtATime() {
    let pool = (1...50).map { vod("\($0)", "片\($0)", time: $0) }
    let all = HomeFeed.allItems(pool)
    let first = HomeFeed.initialAllDisplayCount(allLength: all.count)
    assertEqual(first, 6, "all section should start with one row of 6")
    let rows = HomeFeed.allRows(items: all, displayCount: first)
    assertEqual(rows.count, 1, "first paint should be a single all row")
    assertEqual(rows.first?.map(\.vodId) ?? [], (39...44).reversed().map(String.init), "first all row should be the next 6 newest leftovers")

    let next = HomeFeed.nextAllDisplayCount(current: first, allLength: all.count)
    assertEqual(next, 12, "scrolling down should reveal another 6")
    assertEqual(HomeFeed.allRows(items: all, displayCount: next).count, 2, "second reveal should add a second row")
}

func testNextAllLoadMoreRevealsBeforeFetching() {
    assertEqual(
        HomeFeed.nextAllLoadMore(displayCount: 6, allLength: 38, apiPage: 1, pageCount: 4, isBusy: false),
        .reveal(displayCount: 12),
        "all section should reveal pooled rows before requesting the next API page"
    )
    assertEqual(
        HomeFeed.nextAllLoadMore(displayCount: 38, allLength: 38, apiPage: 1, pageCount: 4, isBusy: false),
        .fetch(page: 2),
        "all section should fetch the next page after the window catches the pool"
    )
    assertEqual(
        HomeFeed.nextAllLoadMore(displayCount: 0, allLength: 0, apiPage: 1, pageCount: 4, isBusy: false),
        .fetch(page: 2),
        "when all is empty but more pages exist, still fetch so later rows can appear"
    )
    assertEqual(
        HomeFeed.nextAllLoadMore(displayCount: 6, allLength: 38, apiPage: 1, pageCount: 4, isBusy: true),
        .idle,
        "should not stack all-section loads while a request is in flight"
    )
}

func testRecentEmptyWhenPoolFitsInHot() {
    let pool = (1...5).map { vod("\($0)", "片\($0)", time: $0) }
    assertEqual(HomeFeed.hotItems(pool).map(\.vodId), (1...5).map(String.init), "undersized pool should all sit on the hot shelf")
    assertEqual(HomeFeed.recentItems(pool).isEmpty, true, "recent shelf should stay hidden until there are more than 6 items")
    assertEqual(HomeFeed.allItems(pool).isEmpty, true, "all section should stay hidden until leftovers exceed the recent cap")
}

func testRecentKeepsOriginalOrderWhenTimesTie() {
    let pool = (1...12).map { vod("\($0)", "片\($0)", time: $0 <= 6 ? $0 : 100) }
    let recent = HomeFeed.recentItems(pool)
    assertEqual(recent.map(\.vodId), ["7", "8", "9", "10", "11", "12"], "equal vodTime should keep incoming order")
}

func testCanLoadMorePagesIgnoresDisplayCount() {
    assertEqual(HomeFeed.canLoadMorePages(apiPage: 1, pageCount: 5), true, "more API pages should load regardless of how many posters are on screen")
    assertEqual(HomeFeed.canLoadMorePages(apiPage: 5, pageCount: 5), false, "last API page should not request another")
    assertEqual(
        HomeFeed.nextPageLoadMore(apiPage: 1, pageCount: 4, isBusy: false),
        .fetch(page: 2),
        "tvOS load more should fetch the next page without a displayCount window"
    )
    assertEqual(
        HomeFeed.nextPageLoadMore(apiPage: 1, pageCount: 4, isBusy: true),
        .idle,
        "tvOS load more should not stack requests while a page is in flight"
    )
}

func testShouldPrefetchMoreOnLastTwoItems() {
    assertEqual(HomeFeed.shouldPrefetchMore(index: 6, itemCount: 8), true, "second-to-last card should prefetch")
    assertEqual(HomeFeed.shouldPrefetchMore(index: 7, itemCount: 8), true, "last card should prefetch")
    assertEqual(HomeFeed.shouldPrefetchMore(index: 5, itemCount: 8), false, "earlier cards should not prefetch")
    assertEqual(HomeFeed.shouldPrefetchMore(index: 0, itemCount: 1), true, "a single remaining card should still prefetch")
    assertEqual(HomeFeed.shouldPrefetchMore(index: 0, itemCount: 0), false, "empty shelf should not prefetch")
}

func testShouldFetchChildrenDirectlyWhenChildIdsAreKnown() {
    assertEqual(
        CategoryListService.shouldFetchChildrenDirectly(knownChildTypeIds: [6, 7, 8]),
        true,
        "parent 全部 with tree child ids should skip the empty parent list request"
    )
    assertEqual(
        CategoryListService.shouldFetchChildrenDirectly(knownChildTypeIds: []),
        false,
        "without known children, keep the existing direct parent fetch"
    )
}

func testFlattenChildPagesKeepsKnownChildIdOrderNotArrivalOrder() {
    let pages = [
        CategoryListService.ChildListPage(childId: 8, list: [raw("c", "丙")], pageCount: 2, total: 2),
        CategoryListService.ChildListPage(childId: 6, list: [raw("a", "甲")], pageCount: 3, total: 10),
        CategoryListService.ChildListPage(childId: 7, list: [raw("b", "乙")], pageCount: 1, total: 4),
    ]
    let flattened = CategoryListService.flattenChildPages(pages, orderedChildIds: [6, 7, 8])
    assertEqual(flattened.items.map(\.vodName), ["甲", "乙", "丙"], "parallel child fetches must be flattened in tree order, not completion order")
    assertEqual(flattened.pageCount, 3, "pageCount should be the max across child pages")
    assertEqual(flattened.total, 16, "total should sum child page totals")
}

func testMergeVodItemsPreservesFirstSeenOrder() {
    let store = SourceStore(sources: [source(1, "A"), source(2, "B")])
    let items = [
        MergeableVodItem(item: raw("1", "甲"), sourceId: 1, sourceName: "A"),
        MergeableVodItem(item: raw("2", "乙"), sourceId: 1, sourceName: "A"),
        MergeableVodItem(item: raw("3", "甲"), sourceId: 2, sourceName: "B"),
        MergeableVodItem(item: raw("4", "丙"), sourceId: 2, sourceName: "B"),
    ]
    let merged = VodMergeService.toVodItems(VodMergeService.mergeVodItems(items, store: store))
    assertEqual(merged.map(\.vodName), ["甲", "乙", "丙"], "search/list merge should keep first-seen title order")
}

func testDefaultPrimaryTypeIdPrefersMovies() {
    let tree = CategoryTreeBuilder.build(from: [
        CategoryDef(typeId: 12, label: "剧集"),
        CategoryDef(typeId: 6, label: "电影"),
        CategoryDef(typeId: 20, label: "动作片"),
        CategoryDef(typeId: 13, label: "综艺"),
    ])
    assertEqual(CategoryTreeBuilder.defaultTypeId(in: tree), 6, "home should open on 电影 instead of unfiltered 全部")
}

func testDefaultPrimaryTypeIdFallsBackToFirstPrimaryWhenMoviesMissing() {
    let tree = CategoryTreeBuilder.build(from: [
        CategoryDef(typeId: 12, label: "剧集"),
        CategoryDef(typeId: 13, label: "综艺"),
    ])
    assertEqual(CategoryTreeBuilder.defaultTypeId(in: tree), 12, "without 电影, use the first primary category")
}

func testEthicalCategoryIsHiddenFromMovieTabsAndChildren() {
    assertEqual(MacCMSCategoryService.isTypeVisible("伦理片"), false, "伦理片 must not appear as a category")
    assertEqual(MacCMSCategoryService.isTypeVisible("伦理"), false, "伦理 must not appear as a category")
    assertEqual(MacCMSCategoryService.isTypeVisible("倫理片"), false, "traditional 倫理片 must not appear as a category")
    assertEqual(MacCMSCategoryService.isTypeVisible("动作片"), true, "normal movie genres stay visible")

    let categories = MacCMSCategoryService.buildCategories(from: [
        VodTypeRaw(typeId: 6, typeName: "电影"),
        VodTypeRaw(typeId: 20, typeName: "动作片"),
        VodTypeRaw(typeId: 21, typeName: "伦理片"),
    ])
    assertEqual(categories.map(\.label).contains("伦理片"), false, "buildCategories should drop 伦理片")
    let tree = CategoryTreeBuilder.build(from: categories)
    assertEqual(
        tree.childrenByParent[6]?.map(\.label) ?? [],
        ["动作片"],
        "电影 children should not include 伦理片"
    )
}

func testEthicalCategoryIsDroppedEvenWhenAlreadyInTheTreeDefs() {
    let tree = CategoryTreeBuilder.build(from: [
        CategoryDef(typeId: 6, label: "电影"),
        CategoryDef(typeId: 20, label: "动作片"),
        CategoryDef(typeId: 21, label: "伦理片"),
        CategoryDef(typeId: 22, label: "倫理片"),
    ])
    assertEqual(
        tree.childrenByParent[6]?.map(\.label) ?? [],
        ["动作片"],
        "iPad/tvOS trees must drop 伦理 even if a source skipped buildCategories"
    )
}

func testEthicalItemsAreHiddenFromMovieGridAndSearch() {
    let tree = movieCategoryTree()
    let items = [
        vod("1", "动作片甲", typeName: "动作片"),
        vod("2", "伦理片乙", typeName: "伦理片"),
        vod("3", "电影里的伦理", typeName: "电影", vodClass: "伦理,剧情"),
        vod("4", "喜剧片丁", typeName: "喜剧片"),
    ]
    let movieAll = CategoryMatch.filter(items, selectedTypeId: 6, tree: tree)
    assertEqual(
        movieAll.map(\.vodName),
        ["动作片甲", "喜剧片丁"],
        "iPad movie grid must not show 伦理 titles under 电影/全部"
    )
    assertEqual(
        CategoryMatch.excludingHidden(items).map(\.vodName),
        ["动作片甲", "喜剧片丁"],
        "search results must also drop 伦理 titles"
    )
}

func playRaw(from: String, url: String, time: Int = 0) -> VodItemRaw {
    VodItemRaw(
        vodId: "1",
        vodName: "片",
        vodPic: "",
        vodRemarks: "",
        vodYear: "",
        vodArea: "",
        vodClass: "",
        vodBlurb: "",
        vodContent: "",
        vodPlayFrom: from,
        vodPlayURL: url,
        typeId: 6,
        typeName: "电影",
        vodTime: time
    )
}

func testMergePlaySourcesDoesNotRepeatMatchingSiteAndLineName() {
    let merged = PlayParser.mergePlaySources(from: [
        .init(source: source(125, "猫眼"), vod: playRaw(from: "mym3u8", url: "HD$https://cdn.example/1.m3u8"))
    ])
    assertEqual(merged.map(\.name), ["猫眼"], "site and line with the same name should show once, not 猫眼 · 猫眼")
}

func testMergePlaySourcesKeepsSitePrefixWhenLineDiffers() {
    let merged = PlayParser.mergePlaySources(from: [
        .init(source: source(33, "无忧"), vod: playRaw(from: "mym3u8", url: "HD$https://cdn.example/1.m3u8"))
    ])
    assertEqual(merged.map(\.name), ["无忧 · 猫眼"], "a site that is not the line brand should keep the combined label")
}

func testMergePlaySourcesCollapsesYunAndM3U8Duplicates() {
    let merged = PlayParser.mergePlaySources(from: [
        .init(
            source: source(163, "速播"),
            vod: playRaw(
                from: "subm3u8$$$subyun$$$hym3u8$$$hyyun",
                url: "HD$https://a.example/1.m3u8$$$HD$https://b.example/1.m3u8$$$HD$https://c.example/1.m3u8$$$HD$https://d.example/1.m3u8"
            )
        )
    ])
    assertEqual(merged.map(\.name).sorted(), ["速播", "速播 · 虎牙"], "m3u8 and yun of the same brand must collapse to one chip")
}

func testMergePlaySourcesPrefersDirectURLWhenCollapsingDuplicates() {
    let merged = PlayParser.mergePlaySources(from: [
        .init(
            source: source(143, "虎牙"),
            vod: playRaw(
                from: "hyyun$$$hym3u8",
                url: "HD$https://parse.example/play$$$HD$https://cdn.example/1.m3u8"
            )
        )
    ])
    assertEqual(merged.count, 1, "虎牙 yun and m3u8 must be one chip")
    assertEqual(merged[0].name, "虎牙", "matching site and line collapse to 虎牙")
    assertEqual(merged[0].episodes.first?.url, "https://cdn.example/1.m3u8", "keep the direct m3u8 line when collapsing")
}

func testPrimaryTabsKeepOnlyTheFourParentCategories() {
    let tree = CategoryTreeBuilder.build(from: [
        CategoryDef(typeId: 6, label: "电影"),
        CategoryDef(typeId: 12, label: "剧集"),
        CategoryDef(typeId: 13, label: "综艺"),
        CategoryDef(typeId: 4, label: "动漫"),
        CategoryDef(typeId: 20, label: "动作片"),
        CategoryDef(typeId: 21, label: "国产剧"),
        CategoryDef(typeId: 30, label: "体育"),
        CategoryDef(typeId: 31, label: "NBA"),
        CategoryDef(typeId: 32, label: "家庭篇"),
        CategoryDef(typeId: 33, label: "足球"),
        CategoryDef(typeId: 34, label: "篮球"),
        CategoryDef(typeId: 35, label: "未分类"),
    ])
    assertEqual(
        tree.primary.map(\.label),
        ["电影", "剧集", "综艺", "动漫"],
        "top tabs should keep only the four parent categories"
    )
    assertEqual(
        tree.childrenByParent[6]?.map(\.label) ?? [],
        ["动作片"],
        "movie children should still nest under 电影"
    )
}

func movieCategoryTree() -> CategoryTree {
    CategoryTreeBuilder.build(from: [
        CategoryDef(typeId: 6, label: "电影"),
        CategoryDef(typeId: 12, label: "剧集"),
        CategoryDef(typeId: 20, label: "动作片"),
        CategoryDef(typeId: 21, label: "喜剧片"),
        CategoryDef(typeId: 22, label: "国产剧"),
    ])
}

func testCategoryMatchDropsComedyFromActionList() {
    let tree = movieCategoryTree()
    let items = [
        vod("1", "动作片甲", typeName: "动作片"),
        vod("2", "喜剧片乙", typeName: "喜剧片"),
        vod("3", "动作片丙", vodClass: "动作,冒险"),
    ]
    let filtered = CategoryMatch.filter(items, selectedTypeId: 20, tree: tree)
    assertEqual(filtered.map(\.vodName), ["动作片甲", "动作片丙"], "comedy must not remain in the 动作片 pool")
}

func testCategoryMatchParentKeepsAllMovieChildren() {
    let tree = movieCategoryTree()
    let items = [
        vod("1", "动作片甲", typeName: "动作片"),
        vod("2", "喜剧片乙", typeName: "喜剧片"),
        vod("3", "剧集丙", typeName: "国产剧"),
    ]
    let filtered = CategoryMatch.filter(items, selectedTypeId: 6, tree: tree)
    assertEqual(filtered.map(\.vodName), ["动作片甲", "喜剧片乙"], "电影/全部 should keep movie children and drop TV series")
}

func testCategoryMatchKeepsUnknownItemsRatherThanEmptyingTheShelf() {
    let tree = movieCategoryTree()
    let items = [vod("1", "无类名片")]
    let filtered = CategoryMatch.filter(items, selectedTypeId: 20, tree: tree)
    assertEqual(filtered.map(\.vodName), ["无类名片"], "items with no type metadata should stay so a bad CMS tag does not blank the row")
}

func testChildTypeIdsOnlyWhenSelectingAParentCategory() {
    let tree = movieCategoryTree()
    assertEqual(HomeLaunch.childTypeIds(tree: tree, typeId: 6), [20, 21], "电影 should fetch known child type ids")
    assertEqual(HomeLaunch.childTypeIds(tree: tree, typeId: 20), [], "动作片 is a leaf and must not fan-out to sibling categories")
}

func testHomeLaunchPayloadDropsOffCategoryItemsFromMoviePool() {
    let categories = [
        CategoryDef(typeId: 6, label: "电影"),
        CategoryDef(typeId: 20, label: "动作片"),
        CategoryDef(typeId: 22, label: "国产剧"),
    ]
    let payload = HomeLaunch.makePayload(
        categories: categories,
        items: [
            vod("1", "动作片甲", typeName: "动作片"),
            vod("2", "剧集乙", typeName: "国产剧"),
        ],
        page: 1,
        pageCount: 1,
        sourceId: 33,
        tvDisplay: false
    )
    assertEqual(payload.snapshot.pool.map(\.vodName), ["动作片甲"], "movie launch pool should drop TV series that leaked into the page")
    assertEqual(payload.sourceId, 33, "payload should carry the catalog source id")
}

func testCatalogAndSearchRequestsAskForDetailSoPostersAreIncluded() {
    let catalog = MacCMSClient.catalogParams(page: 2, typeId: 5)
    assertEqual(catalog["ac"] ?? "", "detail", "MacCMS list omits vod_pic; catalog must request ac=detail")
    assertEqual(catalog["pg"] ?? "", "2", "catalog page must be forwarded")
    assertEqual(catalog["t"] ?? "", "5", "catalog type id must be forwarded")

    let home = MacCMSClient.catalogParams(page: 1, typeId: nil)
    assertEqual(home["ac"] ?? "", "detail", "home catalog must also request posters")
    if home["t"] != nil {
        fail("home catalog must not send a type id")
    }

    let search = MacCMSClient.searchParams(keyword: "鲨笼", page: 3)
    assertEqual(search["ac"] ?? "", "detail", "search list also omits vod_pic unless ac=detail")
    assertEqual(search["wd"] ?? "", "鲨笼", "search keyword must be forwarded")
    assertEqual(search["pg"] ?? "", "3", "search page must be forwarded")
}

func withTempDirectory(_ body: (URL) -> Void) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("topshelf-\(UUID().uuidString)")
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
        fail("could not create temp directory: \(error)")
    }
    defer { try? FileManager.default.removeItem(at: dir) }
    body(dir)
}

func testAppDeepLinkRoundTripsSourceAndVodId() {
    guard let url = AppDeepLink.vodURL(sourceId: 33, vodId: "12345") else {
        fail("vod URL should be constructible")
    }
    assertEqual(url.absoluteString, "multilivetv://vod/33/12345", "deep link should use multilivetv://vod/{sourceId}/{vodId}")
    let parsed = AppDeepLink.parse(url)
    assertEqual(parsed?.sourceId ?? -1, 33, "parsed sourceId")
    assertEqual(parsed?.vodId ?? "", "12345", "parsed vodId")
}

func testAppDeepLinkEncodesSpecialCharactersInVodId() {
    guard let url = AppDeepLink.vodURL(sourceId: 1, vodId: "id with space/slash") else {
        fail("vod URL should encode special characters")
    }
    let parsed = AppDeepLink.parse(url)
    assertEqual(parsed?.sourceId ?? -1, 1, "encoded sourceId")
    assertEqual(parsed?.vodId ?? "", "id with space/slash", "vodId should round-trip through percent-encoding")
}

func testAppDeepLinkRejectsWrongSchemeAndEmptyId() {
    if AppDeepLink.parse(URL(string: "https://example.com/vod/1/2")!) != nil {
        fail("non-app schemes must be ignored")
    }
    if AppDeepLink.vodURL(sourceId: 1, vodId: "  ") != nil {
        fail("blank vodId must not produce a URL")
    }
    if AppDeepLink.parse(URL(string: "multilivetv://vod/1")!) != nil {
        fail("missing vodId path component must be rejected")
    }
}

func testTopShelfStoreSkipsEmptyAndInvalidPics() {
    let snapshots = [
        TopShelfSnapshot(vodId: "1", sourceId: 33, vodName: "无图", vodPic: ""),
        TopShelfSnapshot(vodId: "2", sourceId: 33, vodName: "相对路径", vodPic: "/upload/a.jpg"),
        TopShelfSnapshot(vodId: "3", sourceId: 33, vodName: "有效", vodPic: "https://pic.example.com/a.jpg"),
        TopShelfSnapshot(vodId: "4", sourceId: 33, vodName: "协议相对", vodPic: "//cdn.example.com/b.jpg"),
    ]
    let kept = TopShelfStore.sanitized(snapshots)
    assertEqual(kept.map(\.vodId), ["3", "4"], "only fetchable poster URLs should be kept, in original order")
}

func testTopShelfStoreCapsAtItemLimit() {
    let snapshots = (1...10).map { index in
        TopShelfSnapshot(
            vodId: "\(index)",
            sourceId: 33,
            vodName: "片\(index)",
            vodPic: "https://pic.example.com/\(index).jpg"
        )
    }
    let kept = TopShelfStore.sanitized(snapshots)
    assertEqual(kept.count, TopShelfStore.itemLimit, "Top Shelf should cap at itemLimit")
    assertEqual(kept.first?.vodId ?? "", "1", "cap should keep earliest valid items")
    assertEqual(kept.last?.vodId ?? "", "\(TopShelfStore.itemLimit)", "cap should not skip ahead")
}

func testTopShelfStoreRoundTripsJSON() {
    withTempDirectory { dir in
        let snapshots = [
            TopShelfSnapshot(vodId: "skip", sourceId: 1, vodName: "空", vodPic: ""),
            TopShelfSnapshot(vodId: "keep", sourceId: 33, vodName: "鲨笼绝境", vodPic: "https://pic.example.com/shark.jpg"),
        ]
        if !TopShelfStore.save(snapshots, directory: dir) {
            fail("save to temp directory should succeed")
        }
        let loaded = TopShelfStore.load(directory: dir)
        assertEqual(loaded, [snapshots[1]], "load should return sanitized snapshots")
    }
}

func testRemoteMediaURLParsesPosterAddresses() {
    if RemoteMediaURL.parse("  ") != nil {
        fail("blank poster strings must be treated as missing")
    }
    if RemoteMediaURL.parse("/upload/vod/poster.jpg") != nil {
        fail("relative poster paths are not fetchable and must fall through to detail lookup")
    }

    let direct = RemoteMediaURL.parse("https://pic.example.com/upload/vod/a.jpg")
    assertEqual(direct?.absoluteString ?? "", "https://pic.example.com/upload/vod/a.jpg", "already-valid https posters should pass through")

    let protocolRelative = RemoteMediaURL.parse("//cdn.example.com/p.jpg")
    assertEqual(protocolRelative?.absoluteString ?? "", "https://cdn.example.com/p.jpg", "protocol-relative posters should gain https")

    let encoded = RemoteMediaURL.parse("https://cdn.example.com/封面 1.jpg")
    let encodedString = encoded?.absoluteString ?? ""
    if encoded == nil || encodedString.contains(" ") || !encodedString.contains("%") {
        fail("posters with spaces or unicode must be percent-encoded, got \(encodedString)")
    }
}

func testRemoteMediaURLParsesProtocolRelativeHLS() {
    let url = RemoteMediaURL.parse("//cdn.example/a.m3u8")
    assertEqual(
        url?.absoluteString ?? "",
        "https://cdn.example/a.m3u8",
        "protocol-relative HLS should become https before AVPlayer"
    )
}

func testRemoteImageRequestSendsBrowserUserAgent() {
    let url = URL(string: "https://pic.youkupic.com/upload/a.jpg")!
    let request = RemoteImagePolicy.makeRequest(url: url)
    assertEqual(
        request.value(forHTTPHeaderField: "User-Agent") ?? "",
        NetworkConfig.userAgent,
        "poster downloads must send a browser UA; AsyncImage's session does not"
    )
}

func testRemoteImageRetriesTimeoutsButNotMissingFiles() {
    assertEqual(
        RemoteImagePolicy.shouldRetry(attempt: 1, statusCode: nil, error: URLError(.timedOut)),
        true,
        "CDN handshake timeouts should retry"
    )
    assertEqual(
        RemoteImagePolicy.shouldRetry(attempt: 1, statusCode: nil, error: URLError(.secureConnectionFailed)),
        true,
        "TLS handshake failures should retry"
    )
    assertEqual(
        RemoteImagePolicy.shouldRetry(attempt: 3, statusCode: nil, error: URLError(.timedOut)),
        false,
        "must stop after maxAttempts"
    )
    assertEqual(
        RemoteImagePolicy.shouldRetry(attempt: 1, statusCode: 404, error: nil),
        false,
        "missing posters should not be retried"
    )
}

func testRemoteImageLoaderCoalescesDuplicateURLsAndCaches() {
    runAsync {
        let counter = FetchCounter()
        let loader = RemoteImageLoader { _ in
            await counter.increment()
            try await Task.sleep(nanoseconds: 40_000_000)
            return Data("poster".utf8)
        }
        let url = URL(string: "https://pic.example.com/a.jpg")!
        async let first = loader.data(for: url)
        async let second = loader.data(for: url)
        let (a, b) = try await (first, second)
        assertEqual(a, Data("poster".utf8), "first waiter should receive downloaded bytes")
        assertEqual(b, Data("poster".utf8), "second waiter should receive the same bytes")
        assertEqual(await counter.value, 1, "hero plus shelf card for the same poster must share one download")

        _ = try await loader.data(for: url)
        assertEqual(await counter.value, 1, "later views should hit the memory cache")
    }
}

private actor FetchCounter {
    private var count = 0
    var value: Int { count }
    func increment() {
        count += 1
    }
}

func testHLSPlaylistProbeAcceptsExtM3UBody() {
    let decision = HLSPlaylistProbe.evaluate(
        statusCode: 200,
        contentType: "text/plain",
        body: "#EXTM3U\n#EXTINF:-1,\nhttps://a.example/seg.ts\n",
        pendingAttempt: 0
    )
    assertEqual(decision, .playable, "200 with #EXTM3U body should play even without mpegurl content-type")
}

func testHLSPlaylistProbeAcceptsMpegURLContentType() {
    let decision = HLSPlaylistProbe.evaluate(
        statusCode: 200,
        contentType: "application/vnd.apple.mpegurl; charset=utf-8",
        body: "",
        pendingAttempt: 0
    )
    assertEqual(decision, .playable, "mpegurl content-type should play without requiring a body")
}

func testHLSPlaylistProbeAcceptsExtM3UAfterBOM() {
    let decision = HLSPlaylistProbe.evaluate(
        statusCode: 206,
        contentType: nil,
        body: "\u{FEFF}#EXTM3U\n#EXT-X-TARGETDURATION:4\n",
        pendingAttempt: 0
    )
    assertEqual(decision, .playable, "UTF-8 BOM before #EXTM3U should still count as HLS")
}

func testHLSPlaylistProbeRetriesAcceptedPending() {
    let decision = HLSPlaylistProbe.evaluate(
        statusCode: 202,
        contentType: "application/json",
        body: "{\"status\":\"starting\"}",
        pendingAttempt: 0
    )
    assertEqual(decision, .retry, "202 means the HLS restream is still slicing")
}

func testHLSPlaylistProbeRejectsPendingAfterMaxAttempts() {
    let decision = HLSPlaylistProbe.evaluate(
        statusCode: 202,
        contentType: "application/json",
        body: "{\"status\":\"starting\"}",
        pendingAttempt: HLSPlaylistProbe.maxPendingAttempts - 1
    )
    assertEqual(decision, .reject, "exhausted 202 polling should fail over instead of spinning")
}

func testHLSPlaylistProbeRejectsHTMLErrorPage() {
    let decision = HLSPlaylistProbe.evaluate(
        statusCode: 200,
        contentType: "text/html",
        body: "<!DOCTYPE html><html><body>error</body></html>",
        pendingAttempt: 0
    )
    assertEqual(decision, .reject, "HTML 200 must not be handed to AVPlayer as a playlist")
}

func testHLSPlaylistProbeRejectsNonSuccessStatus() {
    let decision = HLSPlaylistProbe.evaluate(
        statusCode: 404,
        contentType: "application/vnd.apple.mpegurl",
        body: "#EXTM3U\n",
        pendingAttempt: 0
    )
    assertEqual(decision, .reject, "non-2xx playlist fetches should fail over immediately")
}

func testHLSPlaylistProbeDetectsFLVMagic() {
    let body = Data([0x46, 0x4C, 0x56, 0x01, 0x05, 0x00])
    let decision = HLSPlaylistProbe.evaluate(
        statusCode: 200,
        contentType: "application/octet-stream",
        body: body,
        pendingAttempt: 0
    )
    assertEqual(decision, .flv, "FLV magic bytes should select the VLC path, not AVPlayer")
}

func testHLSPlaylistProbeDetectsFLVContentType() {
    let decision = HLSPlaylistProbe.evaluate(
        statusCode: 200,
        contentType: "video/x-flv",
        body: Data(),
        pendingAttempt: 0
    )
    assertEqual(decision, .flv, "video/x-flv should select the VLC path")
}

func testUserFacingErrorDoesNotCallHTTPLiveStreamAWebpage() {
    let message = PlaybackSupport.userFacingError(
        for: "http://222.186.39.21:35466/huya/11602072",
        underlying: nil
    )
    if message.contains("网页") {
        fail("HTTP live FLV URLs must not be described as webpage links")
    }
}

func testLivePlaybackBuildsVLCHTTPOptionsFromHeaders() {
    let options = LivePlayback.vlcHTTPOptions(headers: [
        "User-Agent": "MultiLiveTV/1",
        "Referer": "http://example.com/",
        "Cookie": "a=1",
        "Origin": "http://example.com/",
    ])
    assertEqual(options, [
        ":http-user-agent=MultiLiveTV/1",
        ":http-referrer=http://example.com/",
        ":http-cookie=a=1",
    ], "VLC should receive mapped HTTP header options")
}

func testHLSPlaylistProbeMergesSetCookieIntoPlayerHeaders() {
    let url = URL(string: "https://cdn.example/live.m3u8")!
    let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Set-Cookie": "sid=abc123; Path=/; HttpOnly"]
    )!
    let cookie = LivePlayback.cookieHeader(from: response)
    let headers = LivePlayback.playerHeaders(kodi: ["Referer": "https://a.example/"], cookieHeader: cookie)
    assertEqual(cookie ?? "", "sid=abc123", "probe must surface playlist Set-Cookie")
    assertEqual(headers["Cookie"] ?? "", "sid=abc123", "playlist Set-Cookie must be copied onto AVPlayer requests")
    assertEqual(headers["Referer"] ?? "", "https://a.example/", "Kodi Referer should still be kept")
}

func testHLSPlaylistProbeStartTimeoutFailsOverWhenNotReady() {
    assertEqual(
        HLSPlaylistProbe.shouldFailOverForStartTimeout(
            elapsed: HLSPlaylistProbe.startTimeout,
            isReadyToPlay: false
        ),
        true,
        "start timeout without readyToPlay should fail over to the next stream"
    )
    assertEqual(
        HLSPlaylistProbe.shouldFailOverForStartTimeout(
            elapsed: HLSPlaylistProbe.startTimeout,
            isReadyToPlay: true
        ),
        false,
        "readyToPlay should keep the current stream after the start timeout"
    )
    assertEqual(
        HLSPlaylistProbe.shouldFailOverForStartTimeout(
            elapsed: HLSPlaylistProbe.startTimeout - 1,
            isReadyToPlay: false
        ),
        false,
        "should not fail over before the start timeout elapses"
    )
}

func testLivePlaybackStartTimeoutAdvancesToNextBackupURL() {
    assertEqual(
        HLSPlaylistProbe.shouldFailOverForStartTimeout(
            elapsed: HLSPlaylistProbe.startTimeout,
            isReadyToPlay: false
        ),
        true,
        "a hung HLS start should be treated as a stream failure"
    )
    assertEqual(LivePlayback.nextURLIndex(after: 0, count: 2) ?? -1, 1, "start timeout should try streams[1]")
    assertEqual(LivePlayback.nextURLIndex(after: 1, count: 2) == nil, true, "last stream timeout should stop failing over")
}

func testM3UParserMergesBackupURLsForSameChannel() {
    let text = """
    #EXTM3U
    #EXTINF:-1 tvg-logo="https://cdn.example/cctv1.png" group-title="央视",CCTV1
    https://a.example/cctv1.m3u8
    #EXTINF:-1 group-title="央视",CCTV1
    https://b.example/cctv1.m3u8
    """
    let groups = M3UPlaylistParser.parse(text)
    assertEqual(groups.count, 1, "same group should collapse")
    assertEqual(groups[0].channels.count, 1, "same channel name should collapse")
    assertEqual(groups[0].channels[0].urls, ["https://a.example/cctv1.m3u8", "https://b.example/cctv1.m3u8"], "duplicate names should become backup URLs")
    assertEqual(groups[0].channels[0].logo ?? "", "https://cdn.example/cctv1.png", "logo from the first EXTINF should be kept")
}

func testM3UParserKeepsGroupOrderAndUngroupedFallback() {
    let text = """
    #EXTM3U
    #EXTINF:-1 group-title="卫视",湖南卫视
    https://a.example/hunan.m3u8
    #EXTINF:-1,未知台
    https://a.example/unknown.m3u8
    #EXTINF:-1 group-title="央视",CCTV1
    https://a.example/cctv1.m3u8
    """
    let groups = M3UPlaylistParser.parse(text)
    assertEqual(groups.map(\.name), ["卫视", "未分组", "央视"], "groups should keep first-seen order")
    let merged = M3UPlaylistParser.merge([
        groups,
        M3UPlaylistParser.parse("#EXTINF:-1 group-title=\"卫视\",湖南卫视\nhttps://b.example/hunan.m3u8\n"),
    ])
    assertEqual(merged[0].channels[0].urls.count, 2, "later playlists should append backup URLs onto the same channel")
}

func testLiveStoreIgnoresDisabledAndEmptyURLs() {
    let store = LiveStore(sources: [
        LiveSource(id: 1, name: "关", url: "https://a.example/a.m3u", flag: 1),
        LiveSource(id: 2, name: "空", url: "  ", flag: 0),
        LiveSource(id: 3, name: "开", url: "https://a.example/live.m3u", flag: 0),
    ])
    assertEqual(store.enabled().map(\.id), [3], "only flag 0 with a non-empty URL should be used")
}

func testLivePlaybackAdvancesToNextBackupURL() {
    assertEqual(LivePlayback.nextURLIndex(after: 0, count: 3) ?? -1, 1, "first failure should try the second URL")
    assertEqual(LivePlayback.nextURLIndex(after: 2, count: 3) == nil, true, "last URL should stop failing over")
}

func testM3UParserReadsUnquotedAndSingleQuotedGroupTitle() {
    let text = """
    #EXTM3U
    #EXTINF:-1 group-title=央视,CCTV1
    https://a.example/cctv1.m3u8
    #EXTINF:-1 group-title='卫视',湖南卫视
    https://a.example/hunan.m3u8
    """
    let groups = M3UPlaylistParser.parse(text)
    assertEqual(groups.map(\.name), ["央视", "卫视"], "unquoted and single-quoted group-title should not fall into 未分组")
}

func testM3UParserStripsKodiHeaderSuffixFromURL() {
    let text = """
    #EXTINF:-1 group-title="央视",CCTV1
    https://a.example/cctv1.m3u8|User-Agent=okhttp&Referer=https://a.example/
    """
    let groups = M3UPlaylistParser.parse(text)
    assertEqual(
        groups[0].channels[0].urls,
        ["https://a.example/cctv1.m3u8"],
        "Kodi-style |headers after the URL should be stripped before playback"
    )
}

func testLivePlaybackParsesKodiCookieAndRefererHeaders() {
    let headers = LivePlayback.headersFromKodiSuffix(
        "User-Agent=okhttp&Referer=https://a.example/&Cookie=sid=abc"
    )
    assertEqual(headers["User-Agent"] ?? "", "okhttp", "Kodi User-Agent should map to the HTTP header")
    assertEqual(headers["Referer"] ?? "", "https://a.example/", "Kodi Referer should map to the HTTP header")
    assertEqual(headers["Cookie"] ?? "", "sid=abc", "Kodi Cookie should map to the HTTP header")
}

func testLivePlaybackForwardsSetCookieToPlayerHeader() {
    let url = URL(string: "https://cdn.example/live.m3u8")!
    let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Set-Cookie": "sid=abc123; Path=/; HttpOnly"]
    )!
    assertEqual(
        LivePlayback.cookieHeader(from: response) ?? "",
        "sid=abc123",
        "playlist Set-Cookie must be copied onto AVPlayer requests"
    )
}

func testLivePlaybackMergesWarmedCookieWithKodiHeaders() {
    let headers = LivePlayback.playerHeaders(
        kodi: ["Cookie": "token=1", "Referer": "https://a.example/"],
        cookieHeader: "sid=abc"
    )
    assertEqual(headers["User-Agent"] ?? "", NetworkConfig.userAgent, "live playback still sends a browser UA")
    assertEqual(headers["Referer"] ?? "", "https://a.example/", "explicit Referer from the playlist should be kept")
    assertEqual(headers["Cookie"] ?? "", "token=1; sid=abc", "warmed cookies should be appended to playlist cookies")
}

func testM3UParserKeepsEXTVLCOPTAndKodiHeadersOnStream() {
    let text = """
    #EXTINF:-1 group-title="央视",CCTV1
    #EXTVLCOPT:http-referrer=https://tv.example/
    #EXTVLCOPT:http-cookie=from=vlc
    https://a.example/cctv1.m3u8|Cookie=sid=abc
    """
    let groups = M3UPlaylistParser.parse(text)
    let stream = groups[0].channels[0].streams[0]
    assertEqual(stream.url, "https://a.example/cctv1.m3u8", "playback URL should not include the Kodi suffix")
    assertEqual(stream.headers["Referer"] ?? "", "https://tv.example/", "EXTVLCOPT referrer should become Referer")
    assertEqual(stream.headers["Cookie"] ?? "", "sid=abc", "Kodi URL Cookie should override EXTVLCOPT cookie")
}

func testM3UParserSkipsNonHTTPPlaybackURLs() {
    let text = """
    #EXTM3U
    #EXTINF:-1 group-title="央视",CCTV1
    http://74.91.26.218:82/live/cctv1hd.m3u8
    #EXTINF:-1 group-title="央视",CCTV1
    https://a.example/cctv1.m3u8
    #EXTINF:-1 group-title="地方",云南台
    rtmp://live.example/yunnan
    #EXTINF:-1 group-title="地方",广播
    rtp://239.3.1.1:8000
    """
    let groups = M3UPlaylistParser.parse(text)
    assertEqual(groups.map(\.name), ["央视"], "groups that only have unplayable URLs should be dropped")
    assertEqual(groups[0].channels.count, 1, "same channel name should collapse HTTP and HTTPS into backups")
    assertEqual(
        groups[0].channels[0].urls,
        ["http://74.91.26.218:82/live/cctv1hd.m3u8", "https://a.example/cctv1.m3u8"],
        "HTTP HLS should be kept; rtmp/rtp must still be dropped"
    )
}

func testM3UParserStripsUTF8BOM() {
    let text = "\u{FEFF}#EXTINF:-1 group-title=\"央视\",CCTV1\nhttps://a.example/cctv1.m3u8\n"
    let groups = M3UPlaylistParser.parse(text)
    assertEqual(groups.map(\.name), ["央视"], "UTF-8 BOM should not prevent parsing the first group")
}

func testTxtPlaylistParsesGenreGroupsAndChannels() {
    let text = """
    轮播频道,#genre#
    鹿鼎记,http://a.example/1
    三国演义,https://b.example/2.m3u8
    移动源,#genre#
    CCTV1,http://c.example/cctv1
    """
    let groups = M3UPlaylistParser.parsePlaylist(text)
    assertEqual(groups.map(\.name), ["轮播频道", "移动源"], "txt #genre# headers should become groups in order")
    assertEqual(groups[0].channels.map(\.name), ["鹿鼎记", "三国演义"], "channels should stay under the current genre")
    assertEqual(groups[1].channels[0].urls, ["http://c.example/cctv1"], "http channel URLs should be kept")
}

func testTxtPlaylistSplitsHashBackupURLs() {
    let text = """
    央视,#genre#
    CCTV1,http://a.example/1#https://b.example/2.m3u8
    """
    let groups = M3UPlaylistParser.parsePlaylist(text)
    assertEqual(
        groups[0].channels[0].urls,
        ["http://a.example/1", "https://b.example/2.m3u8"],
        "TVBox # between URLs should become backup lines"
    )
}

func testParsePlaylistStillReadsM3U() {
    let text = """
    #EXTM3U
    #EXTINF:-1 group-title="卫视",湖南卫视
    https://a.example/hunan.m3u8
    """
    let groups = M3UPlaylistParser.parsePlaylist(text)
    assertEqual(groups.map(\.name), ["卫视"], "M3U playlists should still parse after txt support")
    assertEqual(groups[0].channels[0].urls, ["https://a.example/hunan.m3u8"], "M3U URL line should be unchanged")
}

func testLivePlaybackIgnoresStaleFailureEvents() {
    assertEqual(
        LivePlayback.shouldApplyFailure(eventGeneration: 1, currentGeneration: 2),
        false,
        "a failure from a previous URL must not skip the current backup"
    )
    assertEqual(
        LivePlayback.shouldApplyFailure(eventGeneration: 2, currentGeneration: 2),
        true,
        "the current URL's failure should still fail over"
    )
}

func liveChannel(_ name: String, group: String) -> LiveChannel {
    LiveChannel(
        name: name,
        group: group,
        logo: nil,
        streams: [LiveStream(url: "https://a.example/\(name).m3u8")]
    )
}

func testLiveResumePrefersLastWatchedChannel() {
    let cctv1 = liveChannel("CCTV1", group: "央视")
    let cctv2 = liveChannel("CCTV2", group: "央视")
    let hunan = liveChannel("湖南卫视", group: "卫视")
    let groups = [
        LiveGroup(name: "央视", channels: [cctv1, cctv2]),
        LiveGroup(name: "卫视", channels: [hunan]),
    ]
    let resumed = LiveResume.resolve(groups: groups, lastChannelId: hunan.id)
    assertEqual(resumed?.channel.id ?? "", hunan.id, "should restore last watched channel")
    assertEqual(resumed?.group.name ?? "", "卫视", "should restore last watched group")
}

func testLiveResumeFallsBackToFirstChannelWhenLastIdIsUnknown() {
    let cctv1 = liveChannel("CCTV1", group: "央视")
    let groups = [LiveGroup(name: "央视", channels: [cctv1])]
    let resumed = LiveResume.resolve(groups: groups, lastChannelId: "卫视|不存在")
    assertEqual(resumed?.channel.id ?? "", cctv1.id, "unknown last id should fall back to first channel")
}

func testLiveResumeReturnsNilForEmptyGroups() {
    let resumed = LiveResume.resolve(groups: [], lastChannelId: "央视|CCTV1")
    assertEqual(resumed == nil, true, "empty groups should resume nothing")
}

func testLiveChannelNumberIsOneBasedInGroup() {
    let cctv1 = liveChannel("CCTV1", group: "央视")
    let cctv2 = liveChannel("CCTV2", group: "央视")
    let group = LiveGroup(name: "央视", channels: [cctv1, cctv2])
    assertEqual(LiveChannelNumber.displayIndex(in: group, channelId: cctv1.id) ?? -1, 1, "first channel should be 1")
    assertEqual(LiveChannelNumber.displayIndex(in: group, channelId: cctv2.id) ?? -1, 2, "second channel should be 2")
    assertEqual(LiveChannelNumber.displayIndex(in: group, channelId: "卫视|湖南卫视") == nil, true, "unknown channel should have no number")
}

func testLiveWatchMemoryRoundTripsLastChannelId() {
    let suite = "live-watch-memory-test"
    guard let defaults = UserDefaults(suiteName: suite) else {
        fail("could not create UserDefaults suite")
    }
    defaults.removePersistentDomain(forName: suite)
    LiveWatchMemory.save("央视|CCTV3", to: defaults)
    assertEqual(LiveWatchMemory.load(from: defaults) ?? "", "央视|CCTV3", "last channel id should round-trip")
}

func liveZapGroups() -> [LiveGroup] {
    [
        LiveGroup(name: "央视", channels: [
            liveChannel("CCTV1", group: "央视"),
            liveChannel("CCTV2", group: "央视"),
            liveChannel("CCTV3", group: "央视"),
        ]),
        LiveGroup(name: "卫视", channels: [
            liveChannel("湖南卫视", group: "卫视"),
        ]),
    ]
}

func testLiveChannelZapMovesToNextInSameGroup() {
    let groups = liveZapGroups()
    let next = LiveChannelZap.neighbor(groups: groups, currentId: groups[0].channels[0].id, delta: 1)
    assertEqual(next?.channel.name ?? "", "CCTV2", "down should play the next channel in the group")
    assertEqual(next?.group.name ?? "", "央视", "zap should stay in the current group")
}

func testLiveChannelZapMovesToPreviousInSameGroup() {
    let groups = liveZapGroups()
    let previous = LiveChannelZap.neighbor(groups: groups, currentId: groups[0].channels[1].id, delta: -1)
    assertEqual(previous?.channel.name ?? "", "CCTV1", "up should play the previous channel in the group")
}

func testLiveChannelZapWrapsWithinGroupAndDoesNotCrossGroups() {
    let groups = liveZapGroups()
    let afterLast = LiveChannelZap.neighbor(groups: groups, currentId: groups[0].channels[2].id, delta: 1)
    assertEqual(afterLast?.channel.name ?? "", "CCTV1", "next after last should wrap to first in the group")
    let beforeFirst = LiveChannelZap.neighbor(groups: groups, currentId: groups[0].channels[0].id, delta: -1)
    assertEqual(beforeFirst?.channel.name ?? "", "CCTV3", "previous before first should wrap to last in the group")
    assertEqual(afterLast?.group.name ?? "", "央视", "wrap must not jump to 卫视")
}

func testLiveChannelZapFallsBackWhenCurrentIdIsUnknown() {
    let groups = liveZapGroups()
    let pick = LiveChannelZap.neighbor(groups: groups, currentId: "卫视|不存在", delta: 1)
    assertEqual(pick?.channel.name ?? "", "CCTV1", "unknown current id should fall back to first channel")
}

func testLiveChannelZapReturnsNilForEmptyGroups() {
    let pick = LiveChannelZap.neighbor(groups: [], currentId: "央视|CCTV1", delta: 1)
    assertEqual(pick == nil, true, "empty groups should zap nowhere")
}

func testLiveRemoteRouterImmersiveMapsZapGuidePauseAndCycle() {
    assertEqual(
        LiveRemoteRouter.effect(showGuide: false, event: .move(.up)),
        .zap(-1),
        "immersive up should zap previous"
    )
    assertEqual(
        LiveRemoteRouter.effect(showGuide: false, event: .move(.down)),
        .zap(1),
        "immersive down should zap next"
    )
    assertEqual(
        LiveRemoteRouter.effect(showGuide: false, event: .move(.left)),
        .showGuide,
        "immersive left should open the guide"
    )
    assertEqual(
        LiveRemoteRouter.effect(showGuide: false, event: .move(.right)),
        .cycleStream,
        "immersive right should cycle backup streams"
    )
    assertEqual(
        LiveRemoteRouter.effect(showGuide: false, event: .select),
        .showGuide,
        "immersive select should open the guide"
    )
    assertEqual(
        LiveRemoteRouter.effect(showGuide: false, event: .menu),
        .showGuide,
        "immersive menu should open the guide"
    )
    assertEqual(
        LiveRemoteRouter.effect(showGuide: false, event: .playPause),
        .togglePause,
        "immersive play/pause should toggle playback"
    )
}

func testLiveRemoteRouterGuideMapsHideOnMenuAndRight() {
    assertEqual(
        LiveRemoteRouter.effect(showGuide: true, event: .menu),
        .hideGuide,
        "guide menu should hide the guide"
    )
    assertEqual(
        LiveRemoteRouter.effect(showGuide: true, event: .move(.right)),
        .hideGuide,
        "guide right from channel list should hide the guide"
    )
    assertEqual(
        LiveRemoteRouter.effect(showGuide: true, event: .move(.up)),
        .none,
        "guide up should leave focus movement to the list"
    )
    assertEqual(
        LiveRemoteRouter.effect(showGuide: true, event: .select),
        .none,
        "guide select should stay on the focused channel button"
    )
    assertEqual(
        LiveRemoteRouter.effect(showGuide: true, event: .playPause),
        .togglePause,
        "play/pause should still toggle while the guide is open"
    )
}

func testLiveGuideFocusReadsGroupNameFromFocusId() {
    assertEqual(LiveGuideFocus.groupName(fromFocusId: "g:央视") ?? "", "央视", "g: prefix should yield the group name")
    assertEqual(LiveGuideFocus.groupName(fromFocusId: "c:央视|CCTV1") == nil, true, "channel focus must not change group")
    assertEqual(LiveGuideFocus.groupName(fromFocusId: nil) == nil, true, "missing focus should not change group")
    assertEqual(LiveGuideFocus.shouldDismissGuide(focusedId: "dismiss"), true, "landing on the trailing catcher should hide the guide")
    assertEqual(LiveGuideFocus.shouldDismissGuide(focusedId: "c:央视|CCTV1"), false, "channel focus should keep the guide open")
}

func testLivePlaybackManualCycleWrapsWhileFailoverDoesNot() {
    assertEqual(LivePlayback.nextURLIndex(after: 1, count: 2) == nil, true, "failover must stop on the last stream")
    assertEqual(LivePlayback.cycleURLIndex(after: 1, count: 2) ?? -1, 0, "manual cycle should wrap to the first stream")
    assertEqual(LivePlayback.cycleURLIndex(after: 0, count: 2) ?? -1, 1, "manual cycle should advance to the next stream")
    assertEqual(LivePlayback.cycleURLIndex(after: 0, count: 1) == nil, true, "a single stream should not cycle")
}

func testLiveHTTPAcceptsOnly2xx() {
    let url = URL(string: "https://a.example/live.m3u")!
    let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
    assertEqual(LiveHTTP.isSuccess(ok), true, "200 should be accepted")
    assertEqual(LiveHTTP.isSuccess(notFound), false, "404 HTML must not be parsed as a playlist")
}

func testHomeLaunchEntersMainWhenFirstPageSucceedsEvenIfEmpty() {
    assertEqual(HomeLaunch.shouldEnterMain(didSucceed: true), true, "successful home fetch should enter the main UI")
    assertEqual(HomeLaunch.shouldEnterMain(didSucceed: false), false, "failed home fetch should stay on the launch screen")
}

func testHomeLaunchPayloadUsesMovieTypeAndTVAllWindow() {
    let categories = [
        CategoryDef(typeId: 12, label: "剧集"),
        CategoryDef(typeId: 6, label: "电影"),
        CategoryDef(typeId: 20, label: "动作片"),
    ]
    let items = (1...20).map { vod("id-\($0)", "片名\($0)") }
    let payload = HomeLaunch.makePayload(
        categories: categories,
        items: items,
        page: 1,
        pageCount: 5,
        sourceId: 33,
        tvDisplay: true
    )
    assertEqual(payload.selectedTypeId, 6, "launch payload should open on 电影")
    assertEqual(payload.sourceId, 33, "launch payload must keep the catalog source that built the category tree")
    assertEqual(payload.snapshot.pool.count, 20, "first page should become the home pool")
    assertEqual(payload.snapshot.apiPage, 1, "launch snapshot should keep page 1")
    assertEqual(payload.snapshot.pageCount, 5, "launch snapshot should keep the API page count")
    assertEqual(
        payload.snapshot.displayCount,
        HomeFeed.initialAllDisplayCount(allLength: HomeFeed.allItems(payload.snapshot.pool).count),
        "tv launch should use the all-shelf window, not the iPad grid window"
    )
}

func testHomeLaunchLoadFetchesDefaultTypeChildrenThenBuildsPayload() {
    let categories = [
        CategoryDef(typeId: 12, label: "剧集"),
        CategoryDef(typeId: 6, label: "电影"),
        CategoryDef(typeId: 20, label: "动作片"),
    ]
    var requestedTypeId: Int?
    var requestedChildIds: [Int] = []
    let items = [vod("1", "甲"), vod("2", "乙")]

    runAsync {
        let payload = try await HomeLaunch.load(
            fetchCategories: { categories },
            fetchList: { typeId, childIds in
                requestedTypeId = typeId
                requestedChildIds = childIds
                return HomeLaunch.ListPage(items: items, page: 1, pageCount: 3)
            },
            sourceId: 125,
            tvDisplay: true
        )
        assertEqual(payload.snapshot.pool.map(\.vodName), ["甲", "乙"], "launch load should keep first-page order")
        assertEqual(payload.snapshot.pageCount, 3, "launch load should keep pageCount from the list response")
        assertEqual(payload.sourceId, 125, "launch load should pin the source that won the race")
    }

    assertEqual(requestedTypeId, 6, "launch load should request the default 电影 category")
    assertEqual(requestedChildIds, [20], "launch load should pass known child type ids for 电影")
}

func testRequestFailureMapsTimedOutToChinese() {
    let message = RequestFailure.userFacingMessage(for: URLError(.timedOut))
    assertEqual(message, "请求超时，请检查网络后重试", "timeout should not show the system English string")
}

func testRequestFailureMapsNSErrorTimedOutToChinese() {
    let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
    let message = RequestFailure.userFacingMessage(for: error)
    assertEqual(message, "请求超时，请检查网络后重试", "URLSession NSError timeouts should also be Chinese")
}

func testRequestFailureMapsOfflineToChinese() {
    let message = RequestFailure.userFacingMessage(for: URLError(.notConnectedToInternet))
    assertEqual(message, "网络不可用，请检查网络后重试", "offline should be Chinese")
}

func testRequestFailureKeepsAppErrorCopy() {
    let message = RequestFailure.userFacingMessage(for: VodError.sourceNotFound)
    assertEqual(message, "资源站不存在", "existing Chinese app errors should stay unchanged")
}

func testHomeLaunchFirstSuccessUsesLaterSourceWhenEarlierFails() {
    runAsync {
        let value = try await HomeLaunch.firstSuccess(count: 2) { index in
            if index == 0 { throw URLError(.timedOut) }
            return "ok-\(index)"
        }
        assertEqual(value, "ok-1", "launch should fail over to a later source when an earlier one times out")
    }
}

func testHomeLaunchFirstSuccessThrowsWhenEverySourceFails() {
    let thrown = runAsyncExpectingError {
        _ = try await HomeLaunch.firstSuccess(count: 2) { _ in
            throw URLError(.timedOut)
        }
    }
    assertEqual(thrown, true, "launch should surface an error when every source fails")
}

func testHomeLaunchFirstSuccessThrowsWhenCountIsZero() {
    let thrown = runAsyncExpectingError {
        _ = try await HomeLaunch.firstSuccess(count: 0) { _ in "unused" }
    }
    assertEqual(thrown, true, "launch should fail immediately when no sources are enabled")
}

func testHomeLaunchFirstSuccessPrefersFasterSource() {
    runAsync {
        let value = try await HomeLaunch.firstSuccess(count: 2) { index in
            if index == 0 {
                try await Task.sleep(nanoseconds: 200_000_000)
                return "slow"
            }
            return "fast"
        }
        assertEqual(value, "fast", "launch should use the first source that succeeds")
    }
}

func testHomeLaunchFirstSuccessSkipsEmptyWhenLaterSourceHasItems() {
    runAsync {
        let value = try await HomeLaunch.firstSuccess(
            count: 2,
            isAcceptable: { !$0.isEmpty }
        ) { index in
            if index == 0 {
                try await Task.sleep(nanoseconds: 200_000_000)
                return "has-vods"
            }
            return ""
        }
        assertEqual(value, "has-vods", "an empty catalog must not cancel a slower source that actually has items")
    }
}

func testHomeLaunchFirstSuccessFallsBackToEmptyWhenEverySourceIsEmpty() {
    runAsync {
        let value = try await HomeLaunch.firstSuccess(
            count: 2,
            isAcceptable: { !$0.isEmpty }
        ) { _ in
            return ""
        }
        assertEqual(value, "", "if every source returns an empty catalog, keep the empty result instead of hanging")
    }
}

func testRequestGenerationIgnoresCancellationAndStaleEvents() {
    assertEqual(
        RequestGeneration.shouldApply(eventGeneration: 1, currentGeneration: 2),
        false,
        "a dismissed player or superseded search must not apply"
    )
    assertEqual(
        RequestGeneration.shouldApply(eventGeneration: 4, currentGeneration: 4),
        true,
        "the current generation should still apply"
    )
    assertEqual(RequestGeneration.isCancellation(CancellationError()), true, "CancellationError is not a parse failure")
    assertEqual(RequestGeneration.isCancellation(URLError(.cancelled)), true, "URLError.cancelled is not a user-facing failure")
    assertEqual(RequestGeneration.isCancellation(URLError(.timedOut)), false, "timeouts should still surface")
}

private func runAsync(_ work: @escaping () async throws -> Void) {
    let group = DispatchGroup()
    group.enter()
    var caught: String?
    Task {
        do {
            try await work()
        } catch {
            caught = String(describing: error)
        }
        group.leave()
    }
    group.wait()
    if let caught {
        fail("async launch test threw \(caught)")
    }
}

private func runAsyncExpectingError(_ work: @escaping () async throws -> Void) -> Bool {
    let group = DispatchGroup()
    group.enter()
    var thrown = false
    Task {
        do {
            try await work()
        } catch {
            thrown = true
        }
        group.leave()
    }
    group.wait()
    return thrown
}

func testATSAllowsHTTPOnlyWhenConflictingKeysAreAbsent() {
    let ok: [String: Any] = ["NSAllowsArbitraryLoads": true]
    assertEqual(ATSPolicy.allowsInsecureHTTP(ok), true, "NSAllowsArbitraryLoads alone must allow HTTP HLS")

    let withMedia: [String: Any] = [
        "NSAllowsArbitraryLoads": true,
        "NSAllowsArbitraryLoadsForMedia": true,
    ]
    assertEqual(
        ATSPolicy.allowsInsecureHTTP(withMedia),
        false,
        "NSAllowsArbitraryLoadsForMedia makes NSAllowsArbitraryLoads ignored on tvOS 10+"
    )

    let withLocal: [String: Any] = [
        "NSAllowsArbitraryLoads": true,
        "NSAllowsLocalNetworking": true,
    ]
    assertEqual(
        ATSPolicy.allowsInsecureHTTP(withLocal),
        false,
        "NSAllowsLocalNetworking also makes NSAllowsArbitraryLoads ignored"
    )
}

func testDisplayBlurbStripsParagraphTags() {
    let item = VodItem(
        vodId: "1",
        vodName: "致命之旅",
        vodPic: "",
        vodContent: "<p>致命之旅</p>"
    )
    assertEqual(item.displayBlurb ?? "", "致命之旅", "MacCMS HTML tags must not appear in the detail blurb")
}

func testDisplayBlurbStripsTagsFromFallbackBlurb() {
    let item = VodItem(
        vodId: "1",
        vodName: "片名",
        vodPic: "",
        vodBlurb: "<p>简介</p>",
        vodContent: ""
    )
    assertEqual(item.displayBlurb ?? "", "简介", "fallback blurb should also strip HTML")
}

func testDisplayBlurbJoinsAdjacentParagraphsWithSpace() {
    let item = VodItem(
        vodId: "1",
        vodName: "片名",
        vodPic: "",
        vodContent: "<p>第一段</p><p>第二段</p>"
    )
    assertEqual(item.displayBlurb ?? "", "第一段 第二段", "adjacent block tags should not glue words together")
}

func testDisplayBlurbReturnsNilWhenOnlyTagsRemain() {
    let item = VodItem(
        vodId: "1",
        vodName: "片名",
        vodPic: "",
        vodContent: "<p></p>"
    )
    if item.displayBlurb != nil {
        fail("empty HTML should not show a blank blurb")
    }
}

func testUserFacingErrorRewritesATSFailure() {
    let message = PlaybackSupport.userFacingError(
        for: "http://a.example/live.m3u8",
        underlying: "The resource could not be loaded because the App Transport Security policy requires the use of a secure connection."
    )
    if message.lowercased().contains("app transport security") {
        fail("ATS failures must not be shown as the raw English system string")
    }
    assertEqual(message.contains("HTTP"), true, "ATS failure should explain that plaintext HTTP was blocked")
}

@main
enum LogicTests {
    static func main() {
        testMergeIntoPoolPreservesIncomingOrder()
        testMergeIntoPoolKeepsFirstSeenPositionWhenTitleDuplicates()
        testMergeIntoPoolAppendsNewcomersAfterExistingPool()
        testContentPhasePrefersLoadingOverEmpty()
        testContentPhaseEmptyOnlyWhenIdle()
        testCategorySwitchShowsLoadingWhenCacheMisses()
        testCategorySwitchPreservesPagesWhenCacheHits()
        testPullRefreshKeepsPostersWhenFeedHasContent()
        testPullRefreshShowsLoadingWhenFeedIsEmpty()
        testRefreshFirstPageKeepsAlreadyLoadedPages()
        testLoadMoreRevealsBeforeFetching()
        testLoadMoreFetchesNextPageWhenPoolExhausted()
        testLoadMoreIdleWhileBusy()
        testShouldRetriggerLoadMoreFooterWhenDisplayCountChanges()
        testHomeFeedCacheRestoresSnapshotByTypeId()
        testHomeFeedCacheTreatsNilTypeIdAsAllCategory()
        testReplaceFirstPageDropsLeftoverItemsFromPreviousCategory()
        testReplaceFirstPageDedupesAndCapsAtFetchSize()
        testContentPhaseKeepsContentWhileRefreshingCachedPool()
        testHotRecentSplitUsesFirstSixAsHotAndSortsRecentByTime()
        testRecentCapsAtSixAndAllKeepsNewestFirst()
        testAllWindowRevealsSixAtATime()
        testNextAllLoadMoreRevealsBeforeFetching()
        testRecentEmptyWhenPoolFitsInHot()
        testRecentKeepsOriginalOrderWhenTimesTie()
        testCanLoadMorePagesIgnoresDisplayCount()
        testShouldPrefetchMoreOnLastTwoItems()
        testShouldFetchChildrenDirectlyWhenChildIdsAreKnown()
        testFlattenChildPagesKeepsKnownChildIdOrderNotArrivalOrder()
        testMergeVodItemsPreservesFirstSeenOrder()
        testDefaultPrimaryTypeIdPrefersMovies()
        testDefaultPrimaryTypeIdFallsBackToFirstPrimaryWhenMoviesMissing()
        testPrimaryTabsKeepOnlyTheFourParentCategories()
        testEthicalCategoryIsHiddenFromMovieTabsAndChildren()
        testEthicalCategoryIsDroppedEvenWhenAlreadyInTheTreeDefs()
        testEthicalItemsAreHiddenFromMovieGridAndSearch()
        testMergePlaySourcesDoesNotRepeatMatchingSiteAndLineName()
        testMergePlaySourcesKeepsSitePrefixWhenLineDiffers()
        testMergePlaySourcesCollapsesYunAndM3U8Duplicates()
        testMergePlaySourcesPrefersDirectURLWhenCollapsingDuplicates()
        testCategoryMatchDropsComedyFromActionList()
        testCategoryMatchParentKeepsAllMovieChildren()
        testCategoryMatchKeepsUnknownItemsRatherThanEmptyingTheShelf()
        testChildTypeIdsOnlyWhenSelectingAParentCategory()
        testHomeLaunchPayloadDropsOffCategoryItemsFromMoviePool()
        testCatalogAndSearchRequestsAskForDetailSoPostersAreIncluded()
        testAppDeepLinkRoundTripsSourceAndVodId()
        testAppDeepLinkEncodesSpecialCharactersInVodId()
        testAppDeepLinkRejectsWrongSchemeAndEmptyId()
        testTopShelfStoreSkipsEmptyAndInvalidPics()
        testTopShelfStoreCapsAtItemLimit()
        testTopShelfStoreRoundTripsJSON()
        testATSAllowsHTTPOnlyWhenConflictingKeysAreAbsent()
        testUserFacingErrorRewritesATSFailure()
        testRemoteMediaURLParsesPosterAddresses()
        testRemoteMediaURLParsesProtocolRelativeHLS()
        testRemoteImageRequestSendsBrowserUserAgent()
        testRemoteImageRetriesTimeoutsButNotMissingFiles()
        testRemoteImageLoaderCoalescesDuplicateURLsAndCaches()
        testHLSPlaylistProbeAcceptsExtM3UBody()
        testHLSPlaylistProbeAcceptsMpegURLContentType()
        testHLSPlaylistProbeAcceptsExtM3UAfterBOM()
        testHLSPlaylistProbeRetriesAcceptedPending()
        testHLSPlaylistProbeRejectsPendingAfterMaxAttempts()
        testHLSPlaylistProbeRejectsHTMLErrorPage()
        testHLSPlaylistProbeRejectsNonSuccessStatus()
        testHLSPlaylistProbeDetectsFLVMagic()
        testHLSPlaylistProbeDetectsFLVContentType()
        testUserFacingErrorDoesNotCallHTTPLiveStreamAWebpage()
        testLivePlaybackBuildsVLCHTTPOptionsFromHeaders()
        testHLSPlaylistProbeMergesSetCookieIntoPlayerHeaders()
        testHLSPlaylistProbeStartTimeoutFailsOverWhenNotReady()
        testLivePlaybackStartTimeoutAdvancesToNextBackupURL()
        testM3UParserMergesBackupURLsForSameChannel()
        testM3UParserKeepsGroupOrderAndUngroupedFallback()
        testLiveStoreIgnoresDisabledAndEmptyURLs()
        testLivePlaybackAdvancesToNextBackupURL()
        testM3UParserReadsUnquotedAndSingleQuotedGroupTitle()
        testM3UParserStripsKodiHeaderSuffixFromURL()
        testLivePlaybackParsesKodiCookieAndRefererHeaders()
        testLivePlaybackForwardsSetCookieToPlayerHeader()
        testLivePlaybackMergesWarmedCookieWithKodiHeaders()
        testM3UParserKeepsEXTVLCOPTAndKodiHeadersOnStream()
        testM3UParserSkipsNonHTTPPlaybackURLs()
        testM3UParserStripsUTF8BOM()
        testTxtPlaylistParsesGenreGroupsAndChannels()
        testTxtPlaylistSplitsHashBackupURLs()
        testParsePlaylistStillReadsM3U()
        testLivePlaybackIgnoresStaleFailureEvents()
        testLiveResumePrefersLastWatchedChannel()
        testLiveResumeFallsBackToFirstChannelWhenLastIdIsUnknown()
        testLiveResumeReturnsNilForEmptyGroups()
        testLiveChannelNumberIsOneBasedInGroup()
        testLiveWatchMemoryRoundTripsLastChannelId()
        testLiveChannelZapMovesToNextInSameGroup()
        testLiveChannelZapMovesToPreviousInSameGroup()
        testLiveChannelZapWrapsWithinGroupAndDoesNotCrossGroups()
        testLiveChannelZapFallsBackWhenCurrentIdIsUnknown()
        testLiveChannelZapReturnsNilForEmptyGroups()
        testLiveRemoteRouterImmersiveMapsZapGuidePauseAndCycle()
        testLiveRemoteRouterGuideMapsHideOnMenuAndRight()
        testLiveGuideFocusReadsGroupNameFromFocusId()
        testLivePlaybackManualCycleWrapsWhileFailoverDoesNot()
        testLiveHTTPAcceptsOnly2xx()
        testHomeLaunchEntersMainWhenFirstPageSucceedsEvenIfEmpty()
        testHomeLaunchPayloadUsesMovieTypeAndTVAllWindow()
        testHomeLaunchLoadFetchesDefaultTypeChildrenThenBuildsPayload()
        testRequestFailureMapsTimedOutToChinese()
        testRequestFailureMapsNSErrorTimedOutToChinese()
        testRequestFailureMapsOfflineToChinese()
        testRequestFailureKeepsAppErrorCopy()
        testHomeLaunchFirstSuccessUsesLaterSourceWhenEarlierFails()
        testHomeLaunchFirstSuccessThrowsWhenEverySourceFails()
        testHomeLaunchFirstSuccessThrowsWhenCountIsZero()
        testHomeLaunchFirstSuccessPrefersFasterSource()
        testHomeLaunchFirstSuccessSkipsEmptyWhenLaterSourceHasItems()
        testHomeLaunchFirstSuccessFallsBackToEmptyWhenEverySourceIsEmpty()
        testRequestGenerationIgnoresCancellationAndStaleEvents()
        testDisplayBlurbStripsParagraphTags()
        testDisplayBlurbStripsTagsFromFallbackBlurb()
        testDisplayBlurbJoinsAdjacentParagraphsWithSpace()
        testDisplayBlurbReturnsNilWhenOnlyTagsRemain()
        print("VERIFY CLIENT LOGIC PASSED")
    }
}
