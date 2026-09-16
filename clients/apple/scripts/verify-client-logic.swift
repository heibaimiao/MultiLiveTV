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

func vod(_ id: String, _ name: String, time: Int = 0, typeName: String? = nil, vodClass: String? = nil, year: String? = nil) -> VodItem {
    VodItem(vodId: id, vodName: name, vodPic: "", typeName: typeName, vodClass: vodClass, vodYear: year, vodTime: time)
}

func raw(_ id: String, _ name: String, year: String = "", time: Int = 0) -> VodItemRaw {
    VodItemRaw(
        vodId: id,
        vodName: name,
        vodPic: "",
        vodRemarks: "",
        vodYear: year,
        vodArea: "",
        vodClass: "",
        vodBlurb: "",
        vodContent: "",
        vodPlayFrom: "",
        vodPlayURL: "",
        typeId: 0,
        typeName: "",
        vodTime: time
    )
}

func source(
    _ id: Int,
    _ name: String,
    enabled: Bool = true,
    capabilities: SourceCapabilities = .cmsDefaults,
    metadataPriority: Int = 100,
    playPriority: Int = 100
) -> Source {
    Source(
        id: id,
        name: name,
        url: "https://example.com/\(id)/",
        flag: enabled ? 0 : 1,
        jxUrl: nil,
        vipOnly: false,
        capabilities: capabilities,
        metadataPriority: metadataPriority,
        playPriority: playPriority
    )
}

func testMergeIntoPoolPreservesIncomingOrder() {
    let incoming = (1...5).map { vod("id-\($0)", "片名\($0)", time: 100 - $0) }
    let names = HomeFeed.mergeIntoPool(pool: [], incoming: incoming, isFirstBatch: true).map(\.vodName)
    assertEqual(names, incoming.map(\.vodName), "first batch should keep newest-first API order")
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

func testMergeKeyKeepsHomonymousFilmsWithDifferentYears() {
    let hk = vod("1", "兄弟", typeName: "动作片", year: "2007")
    let us = vod("2", "兄弟", typeName: "剧情片", year: "2009")
    let merged = HomeFeed.mergeIntoPool(pool: [], incoming: [hk, us], isFirstBatch: true)
    assertEqual(Set(merged.map(\.vodId)), Set(["1", "2"]), "two films titled 兄弟 in different years must both stay in the list")
    assertEqual(merged.map(\.vodId), ["2", "1"], "newer release year should rank first when times are equal")
}

func testMergeKeyStillCollapsesSameTitleAndYear() {
    let a = vod("1", "兄弟", year: "2009")
    let b = vod("2", "兄弟", year: "2009")
    let merged = HomeFeed.mergeIntoPool(pool: [], incoming: [a, b], isFirstBatch: true)
    assertEqual(merged.map(\.vodId), ["2"], "same title and year is one work and should still collapse")
}

func testMergeKeyTreatsYearSuffixAsTheSameYear() {
    let a = vod("1", "兄弟", year: "2009年")
    let b = vod("2", "兄弟", year: "2009")
    assertEqual(HomeFeed.mergeKey(for: a), HomeFeed.mergeKey(for: b), "2009年 and 2009 must share a merge key")
}

func testVodMergeKeepsHomonymousFilmsWithDifferentYears() {
    let store = SourceStore(sources: [source(1, "A")])
    let items = [
        MergeableVodItem(item: raw("1", "兄弟", year: "2007"), sourceId: 1, sourceName: "A"),
        MergeableVodItem(item: raw("2", "兄弟", year: "2009"), sourceId: 1, sourceName: "A"),
    ]
    let merged = VodMergeService.toVodItems(VodMergeService.mergeVodItems(items, store: store))
    assertEqual(merged.map(\.vodId), ["1", "2"], "search merge must not fold two 兄弟 films from different years")
}

func testUnifiedMergeSortsByVodTimeDesc() {
    let store = SourceStore(sources: [
        source(1, "A"),
        source(2, "B"),
    ])
    let items = [
        MergeableVodItem(item: raw("1", "旧片", time: 100), sourceId: 1, sourceName: "A"),
        MergeableVodItem(item: raw("2", "新片", time: 300), sourceId: 1, sourceName: "A"),
        MergeableVodItem(item: raw("3", "新片", time: 200), sourceId: 2, sourceName: "B"),
    ]
    let merged = VodMergeService.sortMergedByUpdatedDesc(
        VodMergeService.mergeVodItems(items, store: store)
    )
    let names = merged.map(\.item.vodName)
    assertEqual(names, ["新片", "旧片"], "unified category list should be newest first")
    assertEqual(merged[0].item.vodTime, 300, "group should keep the latest variant vodTime")
}

func testMergeFoldsEmptyYearIntoConcreteYear() {
    let store = SourceStore(sources: [source(1, "A"), source(2, "B")])
    let items = [
        MergeableVodItem(item: raw("1", "热血部落", year: "", time: 100), sourceId: 1, sourceName: "A"),
        MergeableVodItem(item: raw("2", "热血部落", year: "2024", time: 200), sourceId: 2, sourceName: "B"),
    ]
    let merged = VodMergeService.mergeVodItems(items, store: store)
    assertEqual(merged.count, 1, "empty-year and concrete-year same title must collapse")
    assertEqual(merged[0].item.vodTime, 200, "collapsed group keeps newest vodTime")
    assertEqual(merged[0].variants.count, 2, "both sources remain as variants")
}

func testMergeKeepsDistinctYearsSeparate() {
    let store = SourceStore(sources: [source(1, "A")])
    let items = [
        MergeableVodItem(item: raw("1", "兄弟", year: "2007", time: 100), sourceId: 1, sourceName: "A"),
        MergeableVodItem(item: raw("2", "兄弟", year: "2009", time: 200), sourceId: 1, sourceName: "A"),
        MergeableVodItem(item: raw("3", "兄弟", year: "", time: 300), sourceId: 1, sourceName: "A"),
    ]
    let merged = VodMergeService.sortMergedByUpdatedDesc(
        VodMergeService.mergeVodItems(items, store: store)
    )
    assertEqual(merged.count, 2, "two concrete years stay separate; empty year folds into newest")
    assertEqual(merged.map(\.item.vodYear).sorted(), ["2007", "2009"], "both concrete years survive")
}

func testSortPrefersReleaseYearOverUpdateTime() {
    let pool = [
        vod("1", "旧片新更", time: 900, year: "2020"),
        vod("2", "新片旧更", time: 100, year: "2026"),
        vod("3", "无年份", time: 999),
    ]
    assertEqual(
        HomeFeed.sortByUpdatedDesc(pool).map(\.vodId),
        ["2", "1", "3"],
        "release year must rank above vodTime; missing year goes last"
    )
}

func testNormalizeYearRejectsFuturePlaceholder() {
    assertEqual(HomeFeed.normalizeYear("2030"), "", "placeholder years beyond next calendar year must not display")
    assertEqual(HomeFeed.normalizeYear("1899"), "", "pre-cinema years must not display")
    let current = Calendar(identifier: .gregorian).component(.year, from: Date())
    assertEqual(HomeFeed.normalizeYear(String(current)), String(current), "current year must stay")
    assertEqual(HomeFeed.normalizeYear(String(current + 1)), String(current + 1), "next year remains allowed for unreleased titles")
    assertEqual(HomeFeed.normalizeYear(String(current + 2)), "", "year+2 must not display")
}

func testFuturePlaceholderKeepsRecentFilmsNearTop() {
    let current = Calendar(identifier: .gregorian).component(.year, from: Date())
    // Dirty CMS year 2030 should still rank as this year (display still hides it).
    let recent = vod("1", "热血部落", time: 1_700_000_000, year: "2030")
    let older = vod("2", "老片", time: 1_600_000_000, year: "2020")
    assertEqual(
        HomeFeed.sortYearValue("2030", vodTime: 1_700_000_000),
        current,
        "future placeholder should rank as current year, not sink to missing"
    )
    assertEqual(
        HomeFeed.sortByUpdatedDesc([older, recent]).map(\.vodId),
        ["1", "2"],
        "2030-placeholder titles must stay ahead of older real years"
    )
}

func testSortBreaksYearTiesWithNewerUpdateTime() {
    let pool = [
        vod("1", "甲", time: 100, year: "2026"),
        vod("2", "乙", time: 300, year: "2026"),
    ]
    assertEqual(
        HomeFeed.sortByUpdatedDesc(pool).map(\.vodId),
        ["2", "1"],
        "same year should fall back to newer vodTime"
    )
}

func testVodItemIdIncludesSource() {
    let a = VodItem(vodId: "10", vodName: "甲", vodPic: "", primarySourceId: 33, vodTime: 1)
    let b = VodItem(vodId: "10", vodName: "乙", vodPic: "", primarySourceId: 125, vodTime: 1)
    assertEqual(a.id == b.id, false, "same vodId from different sources must not share SwiftUI identity")
}

func testMergeIntoPoolAppendsNewcomersAfterExistingPool() {
    let pool = [
        vod("1", "甲", time: 100),
        vod("2", "乙", time: 90),
    ]
    let incoming = [
        vod("3", "丙", time: 95),
        vod("2-new", "乙", time: 80),
        vod("4", "丁", time: 200),
    ]
    let merged = HomeFeed.mergeIntoPool(pool: pool, incoming: incoming, isFirstBatch: false)
    assertEqual(
        merged.map(\.vodName),
        ["丁", "甲", "丙", "乙"],
        "after pagination merge, pool must stay newest vodTime first"
    )
    assertEqual(merged[3].vodId, "2", "existing pool item should keep identity when not overwritten")
}

func testMergeIntoPoolFirstBatchSortsByVodTimeDesc() {
    let incoming = [
        vod("1", "旧", time: 10),
        vod("2", "新", time: 30),
        vod("3", "中", time: 20),
    ]
    let merged = HomeFeed.mergeIntoPool(pool: [], incoming: incoming, isFirstBatch: true)
    assertEqual(merged.map(\.vodName), ["新", "中", "旧"], "first batch should be newest first")
}

func testContentPhasePrefersLoadingOverEmpty() {
    let phase = HomeFeed.contentPhase(isLoading: true, errorMessage: nil, poolIsEmpty: true)
    assertEqual(phase, .loading, "bootstrap with empty pool should show loading, not empty state")
}

func testContentPhaseEmptyOnlyWhenIdle() {
    let phase = HomeFeed.contentPhase(isLoading: false, errorMessage: nil, poolIsEmpty: true)
    assertEqual(phase, .empty, "idle empty pool should show empty state")
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

func testHomeFeedCacheRestoresSnapshotBySlug() {
    var cache = HomeFeedCache()
    let movies = HomeFeedSnapshot(
        pool: [vod("m1", "电影甲"), vod("m2", "电影乙")],
        displayCount: 2,
        apiPage: 1,
        pageCount: 4
    )
    cache.save(movies, slug: "movie")
    cache.save(
        HomeFeedSnapshot(pool: [vod("a1", "动作")], displayCount: 1, apiPage: 1, pageCount: 2),
        slug: "movie-action"
    )

    let restored = cache.snapshot(for: "movie")
    assertEqual(restored?.pool.map(\.vodId) ?? [], ["m1", "m2"], "cache hit should restore the matching slug pool")
    assertEqual(restored?.displayCount ?? 0, 2, "cache hit should restore displayCount")
    assertEqual(restored?.pageCount ?? 0, 4, "cache hit should restore pageCount")
}

func testHomeFeedCacheTreatsNilSlugAsAllCategory() {
    var cache = HomeFeedCache()
    cache.save(
        HomeFeedSnapshot(pool: [vod("all", "首页")], displayCount: 1, apiPage: 1, pageCount: 1),
        slug: nil
    )
    cache.save(
        HomeFeedSnapshot(pool: [vod("m1", "电影")], displayCount: 1, apiPage: 1, pageCount: 1),
        slug: "movie"
    )

    let all = cache.snapshot(for: nil)
    assertEqual(all?.pool.map(\.vodId) ?? [], ["all"], "nil slug should be the 全部 bucket, not collide with movie")
    if cache.snapshot(for: "unknown") != nil {
        fail("unknown slug should be a cache miss")
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
    // Pool stored newest-first (as mergeIntoPool guarantees).
    let pool = (1...20).reversed().map { vod("\($0)", "片\($0)", time: $0) }
    let hot = HomeFeed.hotItems(pool)
    let recent = HomeFeed.recentItems(pool)
    let all = HomeFeed.allItems(pool)
    assertEqual(hot.map(\.vodId), (15...20).reversed().map(String.init), "hot shelf should be the newest 6")
    assertEqual(recent.map(\.vodId), (9...14).reversed().map(String.init), "recent shelf should be the next 6 newest")
    assertEqual(all.map(\.vodId), (1...8).reversed().map(String.init), "all section should continue newest-first after recent")
}

func testRecentCapsAtSixAndAllKeepsNewestFirst() {
    let pool = (1...50).reversed().map { vod("\($0)", "片\($0)", time: $0) }
    let recent = HomeFeed.recentItems(pool)
    let all = HomeFeed.allItems(pool)
    assertEqual(recent.map(\.vodId), (39...44).reversed().map(String.init), "recent should keep only the next 6 after hot")
    assertEqual(all.map(\.vodId), (1...38).reversed().map(String.init), "all should be the remaining leftovers, newest vodTime first")
    assertEqual(all.count, 38, "50-item pool should leave 38 items for the all section")
}

func testAllWindowRevealsSixAtATime() {
    let pool = (1...50).reversed().map { vod("\($0)", "片\($0)", time: $0) }
    let all = HomeFeed.allItems(pool)
    let first = HomeFeed.initialAllDisplayCount(allLength: all.count)
    assertEqual(first, 6, "all section should start with one row of 6")
    let rows = HomeFeed.allRows(items: all, displayCount: first)
    assertEqual(rows.count, 1, "first paint should be a single all row")
    assertEqual(rows.first?.map(\.vodId) ?? [], (33...38).reversed().map(String.init), "first all row should be the next 6 newest leftovers")

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
    let pool = (1...5).reversed().map { vod("\($0)", "片\($0)", time: $0) }
    assertEqual(HomeFeed.hotItems(pool).map(\.vodId), (1...5).reversed().map(String.init), "undersized pool should all sit on the hot shelf")
    assertEqual(HomeFeed.recentItems(pool).isEmpty, true, "recent shelf should stay hidden until there are more than 6 items")
    assertEqual(HomeFeed.allItems(pool).isEmpty, true, "all section should stay hidden until leftovers exceed the recent cap")
}

func testRecentKeepsOriginalOrderWhenTimesTie() {
    // Newest-first pool: hot = first 6, recent = next 6 with equal times — keep stable order.
    let hot = (1...6).map { vod("\($0)", "片\($0)", time: 200 - $0) }
    let tied = (7...12).map { vod("\($0)", "片\($0)", time: 100) }
    let pool = hot + tied
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

func testDefaultPrimarySlugPrefersMovies() {
    let tree = CategoryTreeBuilder.build(from: sampleUnifiedCatalog())
    assertEqual(CategoryTreeBuilder.defaultSlug(in: tree), "movie", "home should open on 电影 instead of unfiltered 全部")
}

func testDefaultPrimarySlugFallsBackToFirstPrimaryWhenMoviesMissing() {
    let tree = CategoryTreeBuilder.build(from: sampleUnifiedCatalog(includeMovie: false))
    assertEqual(CategoryTreeBuilder.defaultSlug(in: tree), "tv", "without 电影, use the first primary category")
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
}

func testEthicalCategoryIsDroppedEvenWhenAlreadyInTheTreeDefs() {
    assertEqual(MacCMSCategoryService.isTypeVisible("伦理片"), false, "伦理片 stays hidden")
    assertEqual(MacCMSCategoryService.isTypeVisible("倫理片"), false, "traditional 倫理片 stays hidden")
}

func testEthicalItemsAreHiddenFromMovieGridAndSearch() {
    let tree = movieCategoryTree()
    let items = [
        vod("1", "动作片甲", typeName: "动作片"),
        vod("2", "伦理片乙", typeName: "伦理片"),
        vod("3", "电影里的伦理", typeName: "电影", vodClass: "伦理,剧情"),
        vod("4", "喜剧片丁", typeName: "喜剧片"),
    ]
    let movieAll = CategoryMatch.filter(items, selectedSlug: "movie", tree: tree)
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
    assertEqual(merged.map(\.name).sorted(), ["速播", "速播 · 虎牙云", "速播 · 虎牙直链"], "虎牙 yun/m3u8 stay separate; 速播 yun/m3u8 still collapse")
}

func testMergePlaySourcesKeepsHuyaYunAndDirectSeparate() {
    let merged = PlayParser.mergePlaySources(from: [
        .init(
            source: source(143, "虎牙"),
            vod: playRaw(
                from: "hyyun$$$hym3u8",
                url: "HD$https://parse.example/play$$$HD$https://cdn.example/1.m3u8"
            )
        )
    ])
    assertEqual(Set(merged.map(\.name)), ["虎牙云", "虎牙直链"], "虎牙 yun and m3u8 use different chips")
    let preferred = merged[PlayLineWeighting.preferredIndex(in: merged)]
    assertEqual(preferred.name, "虎牙直链", "default to the direct 虎牙 line")
    assertEqual(preferred.episodes.first?.url, "https://cdn.example/1.m3u8", "direct m3u8 stays on the 直链 chip")
}

func testHuyaYunAndM3u8UseDifferentLineNames() {
    let sources = PlayParser.parsePlayURL(
        vodPlayFrom: "hyyun$$$hym3u8",
        vodPlayURL: "正片$https://hd.kuktxu.com/play/bDk0qOKa$$$正片$https://hd.kuktxu.com/play/bDk0qOKa/index.m3u8"
    )
    assertEqual(sources.map(\.name), ["虎牙云", "虎牙直链"], "hyyun and hym3u8 must not share 虎牙")
}

func testDisplayPlaySourceNameDoesNotRepeatHuyaPrefix() {
    assertEqual(PlayParser.displayPlaySourceName(sourceName: "虎牙", lineName: "虎牙直链"), "虎牙直链", "site prefix is not repeated")
    assertEqual(PlayParser.displayPlaySourceName(sourceName: "虎牙", lineName: "虎牙云"), "虎牙云", "yun chip keeps 虎牙云")
    assertEqual(PlayParser.displayPlaySourceName(sourceName: "速播", lineName: "虎牙直链"), "速播 · 虎牙直链", "other sites keep the combined label")
}

func testExtractDirectMediaURLFromDPlayerSharePage() {
    let html = """
    <div id="dplayer"></div>
    <script>
        const vid = 'https://hd.kuktxu.com/play/bDk0qOKa/index.m3u8';
        const videoConfig = { url: vid, type: 'hls' };
    </script>
    """
    assertEqual(
        PlayParser.extractDirectMediaURL(from: html),
        "https://hd.kuktxu.com/play/bDk0qOKa/index.m3u8",
        "share pages already embed the real m3u8"
    )
}

func testPlayLineWeightsOrderOfficialBeforeMacCMS() {
    let sources = [
        PlayLineWeighting.annotate(PlaySource(name: "红牛", key: "hn", episodes: [Episode(name: "1", url: "https://a.com/a.m3u8")], sourceId: 1, playFrom: "hnm3u8"), rawPlayFrom: "hnm3u8"),
        PlayLineWeighting.annotate(PlaySource(name: "腾讯", key: "qq", episodes: [Episode(name: "1", url: "resolve://x")], sourceId: nil, mode: "ticket", playFrom: "qq"), rawPlayFrom: "qq"),
        PlayLineWeighting.annotate(PlaySource(name: "4K", key: "c4k", episodes: [Episode(name: "1", url: "resolve://y")], sourceId: nil, mode: "ticket", playFrom: "cloudflare-4k"), rawPlayFrom: "cloudflare-4k"),
        PlayLineWeighting.annotate(PlaySource(name: "官方C", key: "c", episodes: [Episode(name: "1", url: "resolve://z")], sourceId: nil, mode: "ticket", playFrom: "cloudflare"), rawPlayFrom: "cloudflare"),
    ]
    let sorted = PlayLineWeighting.sort(sources)
    assertEqual(sorted.map(\.key), ["qq", "c", "c4k", "hn"], "platform official > bpz5 CDN > MacCMS")
    PlayLineWeighting.ticketEnabled = true
    assertEqual(
        PlayLineWeighting.preferredPlayableIndex(in: sources, ticketEnabled: true),
        1,
        "with ticket enabled prefer highest official line (qq)"
    )
    assertEqual(
        PlayLineWeighting.preferredPlayableIndex(in: sources, ticketEnabled: false),
        0,
        "without ticket skip official and pick hnm3u8"
    )
    PlayLineWeighting.ticketEnabled = true
}

func testDisplayPlaySourcesKeepsWeightedOrder() {
    PlayLineWeighting.table = PlayLineWeights(
        version: 2,
        defaultWeight: 100,
        byPlayFrom: ["qq": 2000, "hnm3u8": 500],
        byProviderId: [:],
        bySourceId: nil
    )
    PlayLineWeighting.playPriorityBySourceId = [:]
    PlayLineWeighting.healthStore = SourceHealthStore()
    defer {
        PlayLineWeighting.table = .bundled
        PlayLineWeighting.healthStore = .shared
    }

    let sources = [
        PlaySource(name: "红牛", key: "hn", episodes: [Episode(name: "1", url: "https://a.com/a.m3u8")], sourceId: 1, mode: "direct", playFrom: "hnm3u8"),
        PlaySource(name: "腾讯", key: "official-qq", episodes: [Episode(name: "1", url: "https://v.qq.com/x/cover/a/b.html")], sourceId: 901, mode: "direct", playFrom: "qq"),
    ]
    let annotated = sources.map { PlayLineWeighting.annotate($0) }
    let display = PlayLineWeighting.forDetailDisplay(annotated)
    assertEqual(display.map(\.key), ["official-qq", "hn"], "detail shows all lines, official first by weight")
    assertEqual(PlayLineWeighting.forDetailDisplay([]).count, 0, "empty stays empty")
}

func testDirectMediaURLRequiresPathExtension() {
    assertEqual(
        PlaybackSupport.isDirectMediaURL("https://cdn.example/2026/index.m3u8"),
        true,
        "real m3u8 path is direct"
    )
    assertEqual(
        PlaybackSupport.isDirectMediaURL("https://cdn.example/play/abc.mp4?token=1"),
        true,
        "mp4 path with query is direct"
    )
    assertEqual(
        PlaybackSupport.isDirectMediaURL("https://jx.m3u8.tv/jiexi/?url=https://v.qq.com/x/cover/a/b.html"),
        false,
        "jiexi host containing m3u8 must not count as direct media"
    )
    assertEqual(
        PlaybackSupport.isDirectMediaURL("https://vod.example/share/abcdef"),
        false,
        "share page is not direct media"
    )
    assertEqual(
        PlaybackSupport.isDirectMediaURL("https://v.qq.com/x/cover/cid/vid.html"),
        false,
        "official html page is not direct media"
    )
}

func testPreferredPlayableIndexSkipsSharePages() {
    let sources = [
        PlaySource(
            name: "分享线",
            key: "share",
            episodes: [Episode(name: "1", url: "https://vod.example/share/abc")],
            sourceId: 1,
            weight: 900,
            mode: "direct",
            playFrom: "share"
        ),
        PlaySource(
            name: "直链",
            key: "m3u8",
            episodes: [Episode(name: "1", url: "https://vod.example/a/index.m3u8")],
            sourceId: 2,
            weight: 100,
            mode: "direct",
            playFrom: "m3u8"
        ),
    ]
    let index = PlayLineWeighting.preferredPlayableIndex(in: sources, ticketEnabled: false)
    assertEqual(index, 1, "skip high-weight share page; pick real m3u8 line")
}

func testVodPlaybackFailoverBuildsBackupCandidates() {
    let sources = [
        PlaySource(
            name: "高权坏线",
            key: "a",
            episodes: [Episode(name: "1", url: "https://a.example/1/index.m3u8")],
            sourceId: 10,
            weight: 800,
            playFrom: "a"
        ),
        PlaySource(
            name: "备用好线",
            key: "b",
            episodes: [Episode(name: "1", url: "https://b.example/1/index.m3u8")],
            sourceId: 20,
            weight: 200,
            playFrom: "b"
        ),
        PlaySource(
            name: "分享不可播",
            key: "c",
            episodes: [Episode(name: "1", url: "https://c.example/share/x")],
            sourceId: 30,
            weight: 900,
            playFrom: "c"
        ),
    ]
    let episode = sources[0].episodes[0]
    let candidates = VodPlaybackFailover.candidates(
        playSources: sources,
        selectedIndex: 0,
        episode: episode,
        fallbackSourceId: 10,
        maxCandidates: 4
    )
    assertEqual(candidates.map(\.sourceId), [10, 20], "primary then other direct m3u8; skip share")
    assertEqual(VodPlaybackFailover.nextIndex(after: 0, count: 2), 1, "can advance to backup")
    assertEqual(VodPlaybackFailover.nextIndex(after: 1, count: 2) == nil, true, "stop after last candidate")
}

func testPlayLineWeightsSourceIdFallback() {
    PlayLineWeighting.table = PlayLineWeights(
        version: 2,
        defaultWeight: 100,
        byPlayFrom: [:],
        byProviderId: [:],
        bySourceId: ["33": 480, "178": 210]
    )
    PlayLineWeighting.playPriorityBySourceId = [:]
    PlayLineWeighting.healthStore = SourceHealthStore()
    defer {
        PlayLineWeighting.table = .bundled
        PlayLineWeighting.healthStore = .shared
    }

    let low = PlayLineWeighting.annotate(
        PlaySource(name: "最大", key: "a", episodes: [Episode(name: "1", url: "https://a.com/a.m3u8")], sourceId: 178, playFrom: "unknownx"),
        rawPlayFrom: "unknownx"
    )
    let high = PlayLineWeighting.annotate(
        PlaySource(name: "无忧", key: "b", episodes: [Episode(name: "1", url: "https://b.com/b.m3u8")], sourceId: 33, playFrom: "unknowny"),
        rawPlayFrom: "unknowny"
    )
    let sorted = PlayLineWeighting.sort([low, high])
    assertEqual(sorted.map(\.key), ["b", "a"], "higher bySourceId weight first")
}

func testPrimaryTabsKeepOnlyUnifiedParents() {
    let tree = CategoryTreeBuilder.build(from: sampleUnifiedCatalog(includeShort: true))
    assertEqual(
        tree.primary.map(\.label),
        ["电影", "剧集", "综艺", "动漫", "短剧"],
        "top tabs should keep only the unified parent categories"
    )
    assertEqual(
        tree.childrenByParent["movie"]?.map(\.label) ?? [],
        ["动作片", "喜剧片"],
        "movie children should still nest under 电影"
    )
}

func sampleUnifiedCatalog(
    includeMovie: Bool = true,
    movieChildren: [(String, String)] = [("movie-action", "动作片"), ("movie-comedy", "喜剧片")],
    includeShort: Bool = false
) -> UnifiedCatalogFile {
    var tree: [UnifiedCategoryNode] = []
    if includeMovie {
        tree.append(UnifiedCategoryNode(
            slug: "movie",
            label: "电影",
            sources: ["33": 6],
            children: movieChildren.map { UnifiedCategoryNode(slug: $0.0, label: $0.1, sources: [:], children: []) }
        ))
    }
    tree.append(UnifiedCategoryNode(slug: "tv", label: "剧集", sources: ["33": 12], children: [
        UnifiedCategoryNode(slug: "tv-cn", label: "国产剧", sources: [:], children: [])
    ]))
    tree.append(UnifiedCategoryNode(slug: "variety", label: "综艺", sources: [:], children: []))
    tree.append(UnifiedCategoryNode(slug: "anime", label: "动漫", sources: [:], children: []))
    if includeShort {
        tree.append(UnifiedCategoryNode(slug: "short", label: "短剧", sources: [:], children: []))
    }
    return UnifiedCatalogFile(version: 1, generatedAt: nil, aliases: nil, defaultSlug: "movie", tree: tree)
}

func movieCategoryTree() -> CategoryTree {
    CategoryTreeBuilder.build(from: sampleUnifiedCatalog())
}


func testCategoryMatchDropsComedyFromActionList() {
    let tree = movieCategoryTree()
    let items = [
        vod("1", "动作片甲", typeName: "动作片"),
        vod("2", "喜剧片乙", typeName: "喜剧片"),
        vod("3", "动作片丙", vodClass: "动作,冒险"),
    ]
    let filtered = CategoryMatch.filter(items, selectedSlug: "movie-action", tree: tree)
    assertEqual(filtered.map(\.vodName), ["动作片甲", "动作片丙"], "comedy must not remain in the 动作片 pool")
}

func testCategoryMatchParentKeepsAllMovieChildren() {
    let tree = movieCategoryTree()
    let items = [
        vod("1", "动作片甲", typeName: "动作片"),
        vod("2", "喜剧片乙", typeName: "喜剧片"),
        vod("3", "剧集丙", typeName: "国产剧"),
    ]
    let filtered = CategoryMatch.filter(items, selectedSlug: "movie", tree: tree)
    assertEqual(filtered.map(\.vodName), ["动作片甲", "喜剧片乙"], "电影/全部 should keep movie children and drop TV series")
}

func testCategoryMatchKeepsUnknownItemsRatherThanEmptyingTheShelf() {
    let tree = movieCategoryTree()
    let items = [vod("1", "无类名片")]
    let filtered = CategoryMatch.filter(items, selectedSlug: "movie-action", tree: tree)
    assertEqual(filtered.map(\.vodName), ["无类名片"], "items with no type metadata should stay so a bad CMS tag does not blank the row")
}

func testParentSlugLookupForUnifiedTree() {
    let tree = movieCategoryTree()
    assertEqual(CategoryTreeBuilder.parentSlug(tree: tree, slug: "movie"), "movie", "movie is its own parent")
    assertEqual(CategoryTreeBuilder.parentSlug(tree: tree, slug: "movie-action"), "movie", "action nests under movie")
}

func testHomeLaunchPayloadDropsOffCategoryItemsFromMoviePool() {
    let tree = CategoryTreeBuilder.build(from: sampleUnifiedCatalog(
        movieChildren: [("movie-action", "动作片")]
    ))
    let payload = HomeLaunch.makePayload(
        tree: tree,
        items: [
            vod("1", "动作片甲", typeName: "动作片"),
            vod("2", "剧集乙", typeName: "国产剧"),
        ],
        page: 1,
        pageCount: 1,
        selectedSlug: "movie",
        tvDisplay: false
    )
    assertEqual(payload.snapshot.pool.map(\.vodName), ["动作片甲"], "movie launch pool should drop TV series that leaked into the page")
    assertEqual(payload.selectedSlug, "movie", "payload should open on movie slug")
}

func testCatalogAndSearchRequestsAskForDetailSoPostersAreIncluded() {
    let catalog = MacCMSClient.catalogParams(page: 2, typeId: 5)
    assertEqual(catalog["ac"] ?? "", "detail", "MacCMS list omits vod_pic; catalog must request ac=detail")
    assertEqual(catalog["pg"] ?? "", "2", "catalog page must be forwarded")
    assertEqual(catalog["t"] ?? "", "5", "catalog type id must be forwarded")
    if catalog["h"] != nil {
        fail("catalog without hours must not send h")
    }

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

func testCatalogParamsForwardsHoursWhenPositive() {
    let recent = MacCMSClient.catalogParams(page: 1, typeId: 1, hours: 24)
    assertEqual(recent["ac"] ?? "", "detail", "hours filter still uses ac=detail")
    assertEqual(recent["t"] ?? "", "1", "type id kept with hours")
    assertEqual(recent["pg"] ?? "", "1", "page kept with hours")
    assertEqual(recent["h"] ?? "", "24", "MacCMS h = recent N hours")

    let allRecent = MacCMSClient.catalogParams(page: 2, typeId: nil, hours: 12)
    assertEqual(allRecent["h"] ?? "", "12", "hours works without type id")
    if allRecent["t"] != nil {
        fail("hours-only catalog must not invent a type id")
    }

    let ignored = MacCMSClient.catalogParams(page: 1, typeId: 3, hours: 0)
    if ignored["h"] != nil {
        fail("hours <= 0 must omit h")
    }
    let ignoredNeg = MacCMSClient.catalogParams(page: 1, typeId: 3, hours: -1)
    if ignoredNeg["h"] != nil {
        fail("negative hours must omit h")
    }
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
        ":http-tls-verify=0",
        ":tls-verify=0",
    ], "VLC should receive mapped HTTP header options")
}

func testLivePlaybackDisablesVLCTLSVerification() {
    let options = LivePlayback.vlcHTTPOptions(headers: [:])
    if !options.contains(":http-tls-verify=0") || !options.contains(":tls-verify=0") {
        fail("expired live CDN certificates must still play in VLC")
    }
}

func testMediaTLSPolicyDetectsExpiredCertificateErrors() {
    assertEqual(
        MediaTLSPolicy.isUntrustedCertificate(URLError(.serverCertificateUntrusted)),
        true,
        "-1202 expired/untrusted CDN certs should be recognized"
    )
    assertEqual(
        MediaTLSPolicy.isUntrustedCertificate(URLError(.serverCertificateHasBadDate)),
        true,
        "expired-date errors should be recognized"
    )
    let wrapped = NSError(
        domain: NSURLErrorDomain,
        code: NSURLErrorServerCertificateUntrusted,
        userInfo: [
            NSUnderlyingErrorKey: NSError(domain: kCFErrorDomainCFNetwork as String, code: -9814)
        ]
    )
    assertEqual(
        MediaTLSPolicy.isUntrustedCertificate(wrapped),
        true,
        "CFNetwork -9814 wrapped in NSURLError -1202 is an expired certificate"
    )
    assertEqual(
        MediaTLSPolicy.isUntrustedCertificate(URLError(.timedOut)),
        false,
        "timeouts are not certificate failures"
    )
}

func testMediaTLSPolicyAllowsServerTrustOnlyWhenRequested() {
    assertEqual(
        MediaTLSPolicy.challengeAction(
            method: NSURLAuthenticationMethodServerTrust,
            hasServerTrust: true,
            allowInvalidCertificates: true
        ),
        .useCredential,
        "live media probing may accept expired certificates"
    )
    assertEqual(
        MediaTLSPolicy.challengeAction(
            method: NSURLAuthenticationMethodServerTrust,
            hasServerTrust: true,
            allowInvalidCertificates: false
        ),
        .performDefaultHandling,
        "strict sessions must keep system certificate validation"
    )
    assertEqual(
        MediaTLSPolicy.challengeAction(
            method: NSURLAuthenticationMethodHTTPBasic,
            hasServerTrust: false,
            allowInvalidCertificates: true
        ),
        .performDefaultHandling,
        "must not intercept HTTP basic auth"
    )
}

func testLivePlaybackUsesVLCWhenPlaylistTLSIsRelaxed() {
    assertEqual(
        LivePlayback.renderer(decision: .playable, relaxedTLS: false),
        LivePlayback.Renderer.avPlayer,
        "valid HTTPS HLS should stay on AVPlayer"
    )
    assertEqual(
        LivePlayback.renderer(decision: .playable, relaxedTLS: true),
        LivePlayback.Renderer.vlc,
        "AVPlayer cannot ignore expired certificates; HLS must fall back to VLC"
    )
    assertEqual(
        LivePlayback.renderer(decision: .flv, relaxedTLS: false),
        LivePlayback.Renderer.vlc,
        "FLV still uses VLC"
    )
    assertEqual(
        LivePlayback.renderer(decision: .reject, relaxedTLS: true) == nil,
        true,
        "a rejected playlist should still fail over"
    )
}

func testUserFacingErrorRewritesExpiredCertificate() {
    let message = PlaybackSupport.userFacingError(
        for: "https://tylive.kan0512.com/norecord/csztv4k_4k.m3u8",
        underlying: "The certificate for this server is invalid. You might be connecting to a server that is pretending to be “tylive.kan0512.com”"
    )
    if message.lowercased().contains("certificate") || message.contains("invalid") {
        fail("expired-certificate playback errors must be Chinese")
    }
}

func testUserFacingErrorRewritesCannotDecode() {
    let message = PlaybackSupport.userFacingError(
        for: "http://218.206.193.218:8888/hls/1/index.m3u8",
        underlying: "Cannot Decode"
    )
    if message.lowercased().contains("cannot") || message.lowercased().contains("decode") {
        fail("MPEG-2 IPTV decode errors must not be shown in English")
    }
}

func testUserFacingErrorRewritesCoreMediaHTTP602() {
    let message = PlaybackSupport.userFacingError(
        for: "http://107.150.60.122/live/cctv1hd.m3u8",
        underlying: "The operation couldn’t be completed. (CoreMediaErrorDomain error -12667 - HTTP 602: (unhandled))"
    )
    if message.lowercased().contains("coremedia") || message.contains("602") || message.contains("couldn’t") {
        fail("AVPlayer HTTP 602 must not be shown as the raw English system string")
    }
}

func testUserFacingErrorKeepsChineseStartTimeout() {
    let message = PlaybackSupport.userFacingError(
        for: "http://a.example/live.m3u8",
        underlying: "起播超时"
    )
    assertEqual(message, "起播超时", "app-authored Chinese errors must not be replaced")
}

func testLivePlaybackRetriesAVPlayerFailureWithVLC() {
    assertEqual(
        LivePlayback.shouldRetryWithVLC(alreadyUsedVLC: false, vlcAvailable: true),
        true,
        "MPEG-2 电信 HLS and HTTP 602 should try VLC on the same URL before the next line"
    )
    assertEqual(
        LivePlayback.shouldRetryWithVLC(alreadyUsedVLC: true, vlcAvailable: true),
        false,
        "after VLC also fails, fail over to the next stream"
    )
    assertEqual(
        LivePlayback.shouldRetryWithVLC(alreadyUsedVLC: false, vlcAvailable: false),
        false,
        "without VLC, skip straight to the next stream"
    )
}

func testLivePlaybackDoesNotForceBrowserUserAgent() {
    let defaults = LivePlayback.playerHeaders(kodi: [:], cookieHeader: nil)
    assertEqual(defaults["User-Agent"] == nil, true, "live must not inject Chrome UA; IPTV CDNs 602 on browser agents")
    let kodi = LivePlayback.playerHeaders(kodi: ["User-Agent": "okhttp"], cookieHeader: nil)
    assertEqual(kodi["User-Agent"] ?? "", "okhttp", "playlist User-Agent should still win")
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

func testM3UParserStripsTVBoxSourceTagFromUDPXYURL() {
    let text = """
    #EXTINF:-1 group-title="央视",CCTV1
    http://yuwentao114.x3322.net:4022/udp/239.252.220.138:5140$【yuwen】
    """
    let groups = M3UPlaylistParser.parse(text)
    assertEqual(
        groups[0].channels[0].urls,
        ["http://yuwentao114.x3322.net:4022/udp/239.252.220.138:5140"],
        "TVBox $source tags must not be sent as part of the UDPXY path"
    )
}

func testLivePlaybackStripsSourceTagButKeepsQueryDollar() {
    assertEqual(
        LivePlayback.stripSourceTag(
            "http://yuwentao114.x3322.net:4022/udp/239.252.220.138:5140$【yuwen】"
        ),
        "http://yuwentao114.x3322.net:4022/udp/239.252.220.138:5140",
        "playback must strip $【yuwen】 before URLSession/VLC"
    )
    assertEqual(
        LivePlayback.stripSourceTag("https://cdn.example/live.m3u8$移动"),
        "https://cdn.example/live.m3u8",
        "TVBox $线路名 after an HLS URL should also be stripped"
    )
    assertEqual(
        LivePlayback.stripSourceTag("https://cdn.example/live.m3u8?txTime=1903e7b17de$LR•IPV4"),
        "https://cdn.example/live.m3u8?txTime=1903e7b17de",
        "TVBox $源名 glued after a query value must still be stripped"
    )
    assertEqual(
        LivePlayback.stripSourceTag("https://cdn.example/live.m3u8?token=$abc&sig=1"),
        "https://cdn.example/live.m3u8?token=$abc&sig=1",
        "a $ inside a real query pair must be kept"
    )
}

func testLivePlaybackPrefersVLCForHTTPMulticastRelay() {
    assertEqual(
        LivePlayback.prefersVLC(for: "http://yuwentao114.x3322.net:4022/udp/239.252.220.138:5140$【yuwen】"),
        true,
        "UDPXY /udp/ relays are MPEG-TS and must skip HLS probing"
    )
    assertEqual(
        LivePlayback.prefersVLC(for: "http://home.example:4022/rtp/239.1.1.1:8000"),
        true,
        "UDPXY /rtp/ relays must also skip HLS probing"
    )
    assertEqual(
        LivePlayback.prefersVLC(for: "https://cdn.example/cctv1.m3u8"),
        false,
        "regular HLS should still be probed and played with AVPlayer"
    )
}

func testHLSPlaylistProbeDetectsMPEGTSContentType() {
    let decision = HLSPlaylistProbe.evaluate(
        statusCode: 200,
        contentType: "video/mp2t",
        body: Data(),
        pendingAttempt: 0
    )
    assertEqual(decision, .mpegts, "video/mp2t should select the VLC path, not AVPlayer")
}

func testHLSPlaylistProbeDetectsMPEGTSSyncByte() {
    var packet = Data([0x47])
    packet.append(Data(repeating: 0, count: 187))
    packet.append(0x47)
    packet.append(Data(repeating: 1, count: 187))
    let decision = HLSPlaylistProbe.evaluate(
        statusCode: 200,
        contentType: "application/octet-stream",
        body: packet,
        pendingAttempt: 0
    )
    assertEqual(decision, .mpegts, "MPEG-TS sync bytes should select the VLC path")
}

func testHLSPlaylistProbeAcceptsMP4Body() {
    var body = Data([0x00, 0x00, 0x00, 0x20])
    body.append(contentsOf: Array("ftypisom".utf8))
    let decision = HLSPlaylistProbe.evaluate(
        statusCode: 200,
        contentType: "video/mp4",
        body: body,
        pendingAttempt: 0
    )
    assertEqual(decision, .playable, "80后 MP4 点播流应走 AVPlayer，不能当非法播放列表丢掉")
}

func testHLSPlaylistProbeSendsJPEGSegmentHLSToVLC() {
    let decision = HLSPlaylistProbe.evaluate(
        statusCode: 200,
        contentType: "application/vnd.apple.mpegurl",
        body: "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4.000,\n/ts/n4da4274.91959332.jpeg?q=1\n",
        pendingAttempt: 0
    )
    assertEqual(decision, .mpegts, "4gtv JPEG-named TS segments need VLC, not AVPlayer")
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
    assertEqual(headers["User-Agent"] == nil, true, "live playback must not inject a browser UA")
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

func testTxtPlaylistStripsSourceTagFromChannelURL() {
    let text = """
    央视,#genre#
    CCTV1,http://home.example:4022/udp/239.252.220.138:5140$【yuwen】
    """
    let groups = M3UPlaylistParser.parsePlaylist(text)
    assertEqual(
        groups[0].channels[0].urls,
        ["http://home.example:4022/udp/239.252.220.138:5140"],
        "txt live lists also attach $source tags that must be stripped"
    )
}

func testTxtPlaylistReadsLeadingCommaChannelName() {
    let text = """
    咪咕源,#genre#
    ,江苏卫视,http://a.example/play/27.m3u8
    """
    let groups = M3UPlaylistParser.parsePlaylist(text)
    assertEqual(groups[0].channels.map(\.name), ["江苏卫视"], "a leading comma is a broken name, not an empty channel")
    assertEqual(groups[0].channels[0].urls, ["http://a.example/play/27.m3u8"], "the URL after the real name should play")
}

func testTxtPlaylistSplitsGluedChannelsMissingNewline() {
    let text = """
    咪咕源,#genre#
    兵团卫视,http://a.example/play/36.m3u8海南广播电视总台新闻频道,http://b.example/962067517
    """
    let groups = M3UPlaylistParser.parsePlaylist(text)
    assertEqual(
        groups[0].channels.map(\.name),
        ["兵团卫视", "海南广播电视总台新闻频道"],
        "two channels glued without a newline must be split"
    )
    assertEqual(groups[0].channels[0].urls, ["http://a.example/play/36.m3u8"], "first URL must not swallow the second channel name")
    assertEqual(groups[0].channels[1].urls, ["http://b.example/962067517"], "glued second channel should keep its own URL")
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

func testHomeLaunchPayloadUsesMovieSlugAndTVAllWindow() {
    let tree = CategoryTreeBuilder.build(from: sampleUnifiedCatalog())
    let items = (1...20).map { vod("id-\($0)", "片名\($0)") }
    let payload = HomeLaunch.makePayload(
        tree: tree,
        items: items,
        page: 1,
        pageCount: 5,
        selectedSlug: "movie",
        tvDisplay: true
    )
    assertEqual(payload.selectedSlug, "movie", "launch payload should open on 电影")
    assertEqual(payload.snapshot.pool.count, 20, "first page should become the home pool")
    assertEqual(payload.snapshot.apiPage, 1, "launch snapshot should keep page 1")
    assertEqual(payload.snapshot.pageCount, 5, "launch snapshot should keep the API page count")
    assertEqual(
        payload.snapshot.displayCount,
        HomeFeed.initialAllDisplayCount(allLength: HomeFeed.allItems(payload.snapshot.pool).count),
        "tv launch should use the all-shelf window, not the iPad grid window"
    )
}

func testHomeLaunchLoadFetchesDefaultSlugThenBuildsPayload() {
    var requestedSlug: String?
    let items = [vod("1", "甲"), vod("2", "乙")]

    runAsync {
        let payload = try await HomeLaunch.load(
            fetchList: { slug in
                requestedSlug = slug
                return HomeLaunch.ListPage(items: items, page: 1, pageCount: 3)
            },
            tvDisplay: true
        )
        assertEqual(payload.snapshot.pool.map(\.vodName), ["甲", "乙"], "launch load should keep first-page order")
        assertEqual(payload.snapshot.pageCount, 3, "launch load should keep pageCount from the list response")
        assertEqual(payload.selectedSlug, "movie", "launch load should select default movie slug")
    }

    assertEqual(requestedSlug, "movie", "launch load should request the default 电影 category")
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

func testSourceRegistryDecodesDualIdAndCapabilities() {
    let json = """
    {
      "version": 1,
      "sources": [
        {
          "source_id": "cms-143",
          "numericId": 143,
          "name": "虎牙",
          "type": "cms",
          "protocol": "json",
          "enabled": true,
          "inApp": true,
          "vip_only": false,
          "connection": {
            "endpoint": "https://www.huyaapi.com/api.php/provide/vod/at/json",
            "jx_url": "https://www.playm3u8.cn/jiexi.php?url="
          },
          "capabilities": {
            "search": true,
            "category": true,
            "detail": true,
            "play": true,
            "pagination": true,
            "live": false
          },
          "adapter": { "type": "cms_json", "parser": "default_cms_parser" },
          "priority": { "metadata_priority": 460, "play_priority": 460 }
        }
      ]
    }
    """.data(using: .utf8)!
    guard let doc = try? JSONDecoder().decode(SourceRegistryDocument.self, from: json) else {
        fail("registry JSON should decode")
    }
    assertEqual(doc.sources.count, 1, "registry should decode one source")
    let source = doc.sources[0]
    assertEqual(source.sourceId, "cms-143", "string source_id")
    assertEqual(source.numericId, 143, "numericId")
    assertEqual(source.id, 143, "Identifiable id aliases numericId")
    assertEqual(source.url, "https://www.huyaapi.com/api.php/provide/vod/at/json", "url compat")
    assertEqual(source.jxUrl ?? "", "https://www.playm3u8.cn/jiexi.php?url=", "jx_url compat")
    assertEqual(source.capabilities.search, true, "search capability")
    assertEqual(source.adapter.type, "cms_json", "adapter type")
    assertEqual(source.priority.metadataPriority, 460, "metadata priority")
}

func testSourceStoreEnabledVsConfiguredAndCollectable() {
    let disabled = source(10, "关", enabled: false)
    let noSearch = source(
        11,
        "无搜",
        capabilities: SourceCapabilities(search: false, category: true, detail: true, play: true, pagination: true, live: false)
    )
    let ok = source(12, "开", metadataPriority: 200, playPriority: 150)
    let store = SourceStore(sources: [disabled, noSearch, ok])

    assertEqual(store.configured(id: 10)?.name, "关", "configured sees disabled sources")
    assertEqual(store.byID(10) == nil, true, "byID skips disabled")
    assertEqual(store.enabled().map(\.id), [11, 12], "enabled excludes disabled")
    assertEqual(store.collectable(capability: \.search).map(\.id), [12], "search collectable skips capability=false")
    assertEqual(store.collectable(capability: \.category).map(\.id), [11, 12], "category still available")
    assertEqual(store.bySourceID("cms-12")?.name, "开", "lookup by string source_id")
    assertEqual(store.metadataPriority(for: 12), 200, "metadata priority from registry")
    assertEqual(store.playPriority(for: 12), 150, "play priority from registry")
}

func testSourceCollectorRejectsDisabledSearchCapability() {
    let src = source(
        99,
        "无搜",
        capabilities: SourceCapabilities(search: false, category: true, detail: true, play: true, pagination: true, live: false)
    )
    let sem = DispatchSemaphore(value: 0)
    var threw = false
    Task {
        do {
            _ = try await SourceCollector.search(source: src, keyword: "庆余年", page: 1)
        } catch {
            threw = true
        }
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 2)
    assertEqual(threw, true, "search with capability=false must not call adapter")
}

func testMacCMSSourceParserBuildsSourceMovie() {
    let src = source(143, "虎牙")
    let raw = VodItemRaw(
        vodId: "12345",
        vodName: "庆余年第二季",
        vodPic: "https://pic.example/a.jpg",
        vodRemarks: "更新至10集",
        vodYear: "2024",
        vodArea: "大陆",
        vodClass: "剧集",
        vodBlurb: "简介",
        vodContent: "长简介",
        vodActor: "张若昀,李沁",
        vodDirector: "孙皓",
        vodPlayFrom: "hym3u8",
        vodPlayURL: "第1集$https://cdn.example/1.m3u8",
        typeId: 2,
        typeName: "剧集",
        vodTime: 1_700_000_000
    )
    let movie = MacCMSSourceParser.toSourceMovie(source: src, raw: raw)
    assertEqual(movie.sourceId, "cms-143", "source_id on SourceMovie")
    assertEqual(movie.sourceMovieId, "12345", "per-source movie id")
    assertEqual(movie.title, "庆余年第二季", "title")
    assertEqual(movie.year, "2024", "year")
    assertEqual(movie.actors, ["张若昀", "李沁"], "actors split")
    assertEqual(movie.director, "孙皓", "director")
    assertEqual(movie.toVodItemRaw().vodId, "12345", "round-trip to VodItemRaw")
}

func testMergeMetadataPrefersHigherPriorityThenCompleteness() {
    let store = SourceStore(sources: [
        source(1, "A", metadataPriority: 90, playPriority: 40),
        source(2, "B", metadataPriority: 50, playPriority: 90),
        source(3, "C", metadataPriority: 50, playPriority: 50),
    ])
    let items = [
        MergeableVodItem(
            item: VodItemRaw(
                vodId: "a", vodName: "庆余年", vodPic: "", vodRemarks: "", vodYear: "2024",
                vodArea: "", vodClass: "", vodBlurb: "", vodContent: "", vodActor: "",
                vodDirector: "", vodPlayFrom: "", vodPlayURL: "", typeId: 1, typeName: "", vodTime: 1
            ),
            sourceId: 1, sourceName: "A"
        ),
        MergeableVodItem(
            item: VodItemRaw(
                vodId: "b", vodName: "庆余年", vodPic: "https://b.example/p.jpg", vodRemarks: "", vodYear: "2024",
                vodArea: "", vodClass: "", vodBlurb: "", vodContent: "", vodActor: "张三,李四",
                vodDirector: "", vodPlayFrom: "", vodPlayURL: "", typeId: 1, typeName: "", vodTime: 1
            ),
            sourceId: 2, sourceName: "B"
        ),
        MergeableVodItem(
            item: VodItemRaw(
                vodId: "c", vodName: "庆余年", vodPic: "https://c.example/p.jpg", vodRemarks: "", vodYear: "2024",
                vodArea: "", vodClass: "", vodBlurb: "", vodContent: "很长的简介内容", vodActor: "张三,李四,王五",
                vodDirector: "", vodPlayFrom: "", vodPlayURL: "", typeId: 1, typeName: "", vodTime: 1
            ),
            sourceId: 3, sourceName: "C"
        ),
    ]
    let merged = VodMergeService.mergeMetadataFields(items, store: store, primary: items[0].item)
    assertEqual(merged.vodPic.contains("c.example") || merged.vodPic.contains("b.example"), true, "pic from priority/completeness")
    assertEqual(merged.vodActor, "张三,李四,王五", "actors prefer more complete at same priority")
    assertEqual(merged.vodContent, "很长的简介内容", "content from more complete source")
}

func testSourceHealthFailureThresholdDoesNotDisable() {
    let health = SourceHealthStore()
    for _ in 0..<4 {
        health.recordFailure(numericId: 143)
        assertEqual(health.status(for: 143).healthy, true, "under threshold still healthy")
    }
    health.recordFailure(numericId: 143)
    let status = health.status(for: 143)
    assertEqual(status.healthy, false, "5 failures → unhealthy")
    assertEqual(status.errorCount, 5, "error_count tracked")

    let src = source(143, "虎牙", enabled: true)
    assertEqual(src.enabled, true, "config enabled stays true when unhealthy")

    health.recordSuccess(numericId: 143)
    assertEqual(health.status(for: 143).healthy, true, "success clears unhealthy")
    assertEqual(health.status(for: 143).errorCount, 0, "success resets error_count")
}

func testEffectivePlayScoreAppliesHealthPenalty() {
    let health = SourceHealthStore()
    for _ in 0..<5 { health.recordFailure(numericId: 33) }
    PlayLineWeighting.healthStore = health
    PlayLineWeighting.table = PlayLineWeights(
        version: 2,
        defaultWeight: 100,
        byPlayFrom: [:],
        byProviderId: [:],
        bySourceId: ["33": 480, "125": 470]
    )
    PlayLineWeighting.playPriorityBySourceId = [:]
    defer {
        PlayLineWeighting.healthStore = .shared
        PlayLineWeighting.table = .bundled
    }

    let unhealthy = PlayLineWeighting.annotate(
        PlaySource(name: "无忧", key: "a", episodes: [Episode(name: "1", url: "https://a.com/a.m3u8")], sourceId: 33),
        rawPlayFrom: "unknown"
    )
    let healthy = PlayLineWeighting.annotate(
        PlaySource(name: "猫眼", key: "b", episodes: [Episode(name: "1", url: "https://b.com/b.m3u8")], sourceId: 125),
        rawPlayFrom: "unknown"
    )
    assertEqual(unhealthy.weight < healthy.weight, true, "unhealthy source should rank below healthy despite higher base priority")
    let sorted = PlayLineWeighting.sort([unhealthy, healthy])
    assertEqual(sorted.map(\.key), ["b", "a"], "health penalty flips play order")
}

func testAppDeepLinkStillUsesNumericSourceId() {
    guard let url = AppDeepLink.vodURL(sourceId: 143, vodId: "999") else {
        fail("deep link should build")
    }
    assertEqual(url.absoluteString, "multilivetv://vod/143/999", "deep link keeps numeric source id")
    let parsed = AppDeepLink.parse(url)
    assertEqual(parsed?.sourceId ?? -1, 143, "parsed numeric sourceId")
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

func historyRecord(
    videoId: String,
    positionMs: Int64 = 1_000,
    durationMs: Int64 = 7_200_000,
    episodeId: String = "ep1",
    episodeTitle: String = "第1集",
    episodeIndex: Int = 0,
    title: String = "片名",
    lastPlayTime: Int64 = 1_000
) -> WatchHistoryRecord {
    WatchHistoryRecord(
        videoId: videoId,
        vodId: videoId.split(separator: ":").last.map(String.init) ?? videoId,
        episodeId: episodeId,
        title: title,
        episodeTitle: episodeTitle,
        episodeIndex: episodeIndex,
        cover: "https://cover",
        sourceId: 1,
        sourceName: "线路1",
        positionMs: positionMs,
        durationMs: durationMs,
        lastPlayTime: lastPlayTime
    )
}

func testWatchHistoryStoreUpsertsSameVideo() {
    let store = WatchHistoryStore(persistence: MemoryWatchHistoryPersistence())
    store.save(historyRecord(videoId: "1:1001", positionMs: 120_000, lastPlayTime: 10))
    store.save(historyRecord(videoId: "1:1001", positionMs: 860_000, lastPlayTime: 20))
    assertEqual(store.getAll().count, 1, "same videoId should replace, not duplicate")
    assertEqual(store.getAll()[0].positionMs, 860_000, "later position should win")
}

func testWatchHistorySeriesKeepsOnlyLatestEpisode() {
    let store = WatchHistoryStore(persistence: MemoryWatchHistoryPersistence())
    store.save(historyRecord(videoId: "1:dpcq", episodeId: "123", episodeTitle: "第123集", episodeIndex: 122, lastPlayTime: 1))
    store.save(historyRecord(videoId: "1:dpcq", episodeId: "125", episodeTitle: "第125集", episodeIndex: 124, lastPlayTime: 2))
    assertEqual(store.getByVideoId("1:dpcq")?.episodeId ?? "", "125", "series should keep the latest episode")
    assertEqual(store.getAll().count, 1, "one row per video")
}

func testWatchHistorySortsByLastPlayTimeAndTrims() {
    let store = WatchHistoryStore(persistence: MemoryWatchHistoryPersistence(), maxSize: 2)
    store.save(historyRecord(videoId: "a", title: "A", lastPlayTime: 1))
    store.save(historyRecord(videoId: "b", title: "B", lastPlayTime: 2))
    store.save(historyRecord(videoId: "c", title: "C", lastPlayTime: 3))
    assertEqual(store.getAll().map(\.videoId), ["c", "b"], "trim oldest by lastPlayTime")
}

func testWatchHistoryDeleteClearAndCorruptJson() {
    let persistence = MemoryWatchHistoryPersistence()
    persistence.save("{not-json")
    let store = WatchHistoryStore(persistence: persistence)
    assertEqual(store.getAll().isEmpty, true, "corrupt json should load as empty")
    store.save(historyRecord(videoId: " "))
    store.save(historyRecord(videoId: ""))
    assertEqual(store.getAll().isEmpty, true, "blank videoId should be skipped")
    store.save(historyRecord(videoId: "a"))
    store.save(historyRecord(videoId: "b"))
    store.delete("a")
    assertEqual(store.getAll().map(\.videoId), ["b"], "delete should drop one row")
    store.clear()
    assertEqual(store.getAll().isEmpty, true, "clear should empty the store")
}

func testWatchHistoryFilePersistenceSurvivesReload() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("watch-history-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("watch_history.json")
    defer {
        try? FileManager.default.removeItem(at: dir)
    }
    WatchHistoryStore(persistence: FileWatchHistoryPersistence(file: file))
        .save(historyRecord(videoId: "1:1001", positionMs: 5_000))
    let reloaded = WatchHistoryStore(persistence: FileWatchHistoryPersistence(file: file)).getByVideoId("1:1001")
    assertEqual(reloaded?.positionMs ?? -1, 5_000, "file persistence should round-trip")
}

func testWatchHistoryProgressSanitizesAndCompletesNearEnd() {
    assertEqual(WatchHistoryProgress.sanitizePosition(-10, durationMs: 1_000), 0, "negative clamps to 0")
    assertEqual(WatchHistoryProgress.sanitizePosition(800, durationMs: 1_000), 800, "in-range stays")
    assertEqual(WatchHistoryProgress.sanitizePosition(2_000, durationMs: 1_000), 1_000, "over duration clamps")
    assertEqual(WatchHistoryProgress.sanitizePosition(10, durationMs: 0), 0, "unknown duration is 0")
    assertEqual(WatchHistoryProgress.isCompleted(1_790_000, durationMs: 1_800_000), true, "within 10s of end is complete")
    assertEqual(WatchHistoryProgress.isCompleted(1_000, durationMs: 10_000), false, "early position is not complete")
    let completed = WatchHistoryProgress.normalize(historyRecord(videoId: "1:1", positionMs: 7_191_000, durationMs: 7_200_000))
    assertEqual(completed.completed, true, "normalize should mark near-end complete")
    assertEqual(WatchHistoryResume.resumePositionMs(completed), 0, "completed resume starts over")
    assertEqual(
        WatchHistoryResume.resumePositionMs(historyRecord(videoId: "1:1", positionMs: 185_000, durationMs: 7_200_000)),
        185_000,
        "in-progress resume keeps position"
    )
}

func testWatchHistoryRecorderThrottlesUntilForced() {
    let store = WatchHistoryStore(persistence: MemoryWatchHistoryPersistence())
    let recorder = WatchHistoryRecorder(store: store, intervalMs: 8_000)
    recorder.save(historyRecord(videoId: "1:1", positionMs: 1_000, lastPlayTime: 10_000), force: false)
    recorder.save(historyRecord(videoId: "1:1", positionMs: 2_000, lastPlayTime: 14_000), force: false)
    assertEqual(store.getByVideoId("1:1")?.positionMs ?? -1, 1_000, "throttle should drop the 4s update")
    recorder.save(historyRecord(videoId: "1:1", positionMs: 3_000, lastPlayTime: 14_000), force: true)
    assertEqual(store.getByVideoId("1:1")?.positionMs ?? -1, 3_000, "force should write immediately")
    recorder.save(historyRecord(videoId: "1:1", positionMs: 4_000, lastPlayTime: 22_000), force: false)
    assertEqual(store.getByVideoId("1:1")?.positionMs ?? -1, 4_000, "interval elapsed should write again")
}

func testWatchHistoryResumeFindsEpisodeByIdThenNameThenIndex() {
    let episodes = [Episode(name: "第1集", url: "u1"), Episode(name: "第3集", url: "u3"), Episode(name: "第5集", url: "u5")]
    let detail = DetailResponse(
        vod: VodItem(vodId: "1001", vodName: "斗破苍穹", vodPic: ""),
        playSources: [PlaySource(name: "线路1", key: "line1", episodes: episodes, sourceId: 7)],
        variants: [],
        merged: false
    )
    let matched = WatchHistoryResume.findEpisode(detail: detail, record: historyRecord(videoId: "7:1001", episodeId: "u3", episodeTitle: "第3集", episodeIndex: 1))
    assertEqual(matched?.1.url ?? "", "u3", "match by episode url")
    let byName = WatchHistoryResume.findEpisode(detail: detail, record: historyRecord(videoId: "7:1001", episodeId: "missing", episodeTitle: "第5集", episodeIndex: 0))
    assertEqual(byName?.1.url ?? "", "u5", "fall back to episode title")
    let byIndex = WatchHistoryResume.findEpisode(detail: detail, record: historyRecord(videoId: "7:1001", episodeId: "", episodeTitle: "", episodeIndex: 0))
    assertEqual(byIndex?.1.url ?? "", "u1", "fall back to episode index")
    let empty = WatchHistoryResume.findEpisode(
        detail: DetailResponse(vod: detail.vod, playSources: [], variants: [], merged: false),
        record: historyRecord(videoId: "7:1001")
    )
    assertEqual(empty == nil, true, "empty sources cannot resume")
}

func testWatchHistoryDisplayCopyAndEpisodeLine() {
    assertEqual(WatchHistoryDisplay.heading(), "接着看", "heading")
    assertEqual(WatchHistoryDisplay.continueAction(clock: "0:04"), "从 0:04 继续", "continue")
    assertEqual(WatchHistoryDisplay.restartAction(), "从头播放", "restart")
    assertEqual(WatchHistoryDisplay.episodeLine(title: "保镖恋人", episodeTitle: "HD") == nil, true, "drop HD")
    assertEqual(WatchHistoryDisplay.episodeLine(title: "保镖恋人", episodeTitle: "1080P") == nil, true, "drop 1080P")
    assertEqual(WatchHistoryDisplay.episodeLine(title: "保镖恋人", episodeTitle: "保镖恋人") == nil, true, "drop duplicate title")
    assertEqual(WatchHistoryDisplay.episodeLine(title: "保镖恋人", episodeTitle: "正片") == nil, true, "drop 正片")
    assertEqual(WatchHistoryDisplay.episodeLine(title: "保镖恋人", episodeTitle: "第12集") ?? "", "第12集", "keep real episode")
    assertEqual(WatchHistoryDisplay.episodeLine(title: "保镖恋人", episodeTitle: "HD第12集") ?? "", "HD第12集", "keep mixed label")
    assertEqual(WatchHistoryProgress.formatClock(0), "0:00", "zero clock")
    assertEqual(WatchHistoryProgress.formatClock(185_000), "3:05", "minutes clock")
    assertEqual(WatchHistoryProgress.formatClock(6_750_000), "1:52:30", "hours clock")
    assertEqual(WatchHistoryDisplay.showProgressBar(7_200_000), true, "known duration shows bar")
    assertEqual(WatchHistoryDisplay.showProgressBar(0), false, "unknown duration hides bar")
}

func testEpisodePagingSplitsLongSeries() {
    let movie = EpisodePaging.pages(count: 1)
    assertEqual(movie.map(\.label), ["1-1"], "movie is one page")
    assertEqual(EpisodePaging.slice(["正片"], page: movie[0]), ["正片"], "movie slice")
    let pages = EpisodePaging.pages(count: 86, pageSize: 40)
    assertEqual(pages.map(\.label), ["1-40", "41-80", "81-86"], "long series splits")
    let names = (1...86).map { "第\($0)集" }
    assertEqual(EpisodePaging.slice(names, page: pages[0]).count, 40, "first page size")
    assertEqual(EpisodePaging.slice(names, page: pages[1]).first ?? "", "第41集", "second page starts at 41")
    let last = EpisodePaging.slice(names, page: pages[2])
    assertEqual([last.first ?? "", last.last ?? ""], ["第81集", "第86集"], "last page range")
}

func testAsyncTimeoutDropsLateValue() {
    let sem = DispatchSemaphore(value: 0)
    var late: String? = "unset"
    var early: String? = nil
    Task {
        late = await AsyncTimeout.run(seconds: 0.05) {
            try await Task.sleep(nanoseconds: 400_000_000)
            return "late"
        }
        early = await AsyncTimeout.run(seconds: 1) {
            return "ok"
        }
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 2)
    assertEqual(late == nil, true, "timeout should drop the late value")
    assertEqual(early ?? "", "ok", "fast value should return before deadline")
}

@main
enum LogicTests {
    static func main() {
        testMergeIntoPoolPreservesIncomingOrder()
        testMergeIntoPoolKeepsFirstSeenPositionWhenTitleDuplicates()
        testMergeKeyKeepsHomonymousFilmsWithDifferentYears()
        testMergeKeyStillCollapsesSameTitleAndYear()
        testMergeKeyTreatsYearSuffixAsTheSameYear()
        testMergeIntoPoolAppendsNewcomersAfterExistingPool()
        testMergeIntoPoolFirstBatchSortsByVodTimeDesc()
        testContentPhasePrefersLoadingOverEmpty()
        testContentPhaseEmptyOnlyWhenIdle()
        testLoadMoreRevealsBeforeFetching()
        testLoadMoreFetchesNextPageWhenPoolExhausted()
        testLoadMoreIdleWhileBusy()
        testShouldRetriggerLoadMoreFooterWhenDisplayCountChanges()
        testHomeFeedCacheRestoresSnapshotBySlug()
        testHomeFeedCacheTreatsNilSlugAsAllCategory()
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
        testVodMergeKeepsHomonymousFilmsWithDifferentYears()
        testUnifiedMergeSortsByVodTimeDesc()
        testMergeFoldsEmptyYearIntoConcreteYear()
        testMergeKeepsDistinctYearsSeparate()
        testSortPrefersReleaseYearOverUpdateTime()
        testNormalizeYearRejectsFuturePlaceholder()
        testFuturePlaceholderKeepsRecentFilmsNearTop()
        testSortBreaksYearTiesWithNewerUpdateTime()
        testVodItemIdIncludesSource()
        testDefaultPrimarySlugPrefersMovies()
        testDefaultPrimarySlugFallsBackToFirstPrimaryWhenMoviesMissing()
        testPrimaryTabsKeepOnlyUnifiedParents()
        testEthicalCategoryIsHiddenFromMovieTabsAndChildren()
        testEthicalCategoryIsDroppedEvenWhenAlreadyInTheTreeDefs()
        testEthicalItemsAreHiddenFromMovieGridAndSearch()
        testMergePlaySourcesDoesNotRepeatMatchingSiteAndLineName()
        testMergePlaySourcesKeepsSitePrefixWhenLineDiffers()
        testMergePlaySourcesCollapsesYunAndM3U8Duplicates()
        testMergePlaySourcesKeepsHuyaYunAndDirectSeparate()
        testHuyaYunAndM3u8UseDifferentLineNames()
        testDisplayPlaySourceNameDoesNotRepeatHuyaPrefix()
        testExtractDirectMediaURLFromDPlayerSharePage()
        testPlayLineWeightsOrderOfficialBeforeMacCMS()
        testDisplayPlaySourcesKeepsWeightedOrder()
        testDirectMediaURLRequiresPathExtension()
        testPreferredPlayableIndexSkipsSharePages()
        testVodPlaybackFailoverBuildsBackupCandidates()
        testPlayLineWeightsSourceIdFallback()
        testCategoryMatchDropsComedyFromActionList()
        testCategoryMatchParentKeepsAllMovieChildren()
        testCategoryMatchKeepsUnknownItemsRatherThanEmptyingTheShelf()
        testParentSlugLookupForUnifiedTree()
        testHomeLaunchPayloadDropsOffCategoryItemsFromMoviePool()
        testCatalogAndSearchRequestsAskForDetailSoPostersAreIncluded()
        testCatalogParamsForwardsHoursWhenPositive()
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
        testLivePlaybackDisablesVLCTLSVerification()
        testMediaTLSPolicyDetectsExpiredCertificateErrors()
        testMediaTLSPolicyAllowsServerTrustOnlyWhenRequested()
        testLivePlaybackUsesVLCWhenPlaylistTLSIsRelaxed()
        testUserFacingErrorRewritesExpiredCertificate()
        testUserFacingErrorRewritesCannotDecode()
        testUserFacingErrorRewritesCoreMediaHTTP602()
        testUserFacingErrorKeepsChineseStartTimeout()
        testLivePlaybackRetriesAVPlayerFailureWithVLC()
        testLivePlaybackDoesNotForceBrowserUserAgent()
        testHLSPlaylistProbeMergesSetCookieIntoPlayerHeaders()
        testHLSPlaylistProbeStartTimeoutFailsOverWhenNotReady()
        testLivePlaybackStartTimeoutAdvancesToNextBackupURL()
        testM3UParserMergesBackupURLsForSameChannel()
        testM3UParserKeepsGroupOrderAndUngroupedFallback()
        testLiveStoreIgnoresDisabledAndEmptyURLs()
        testLivePlaybackAdvancesToNextBackupURL()
        testM3UParserReadsUnquotedAndSingleQuotedGroupTitle()
        testM3UParserStripsKodiHeaderSuffixFromURL()
        testM3UParserStripsTVBoxSourceTagFromUDPXYURL()
        testLivePlaybackStripsSourceTagButKeepsQueryDollar()
        testLivePlaybackPrefersVLCForHTTPMulticastRelay()
        testHLSPlaylistProbeDetectsMPEGTSContentType()
        testHLSPlaylistProbeDetectsMPEGTSSyncByte()
        testHLSPlaylistProbeAcceptsMP4Body()
        testHLSPlaylistProbeSendsJPEGSegmentHLSToVLC()
        testLivePlaybackParsesKodiCookieAndRefererHeaders()
        testLivePlaybackForwardsSetCookieToPlayerHeader()
        testLivePlaybackMergesWarmedCookieWithKodiHeaders()
        testM3UParserKeepsEXTVLCOPTAndKodiHeadersOnStream()
        testM3UParserSkipsNonHTTPPlaybackURLs()
        testM3UParserStripsUTF8BOM()
        testTxtPlaylistParsesGenreGroupsAndChannels()
        testTxtPlaylistSplitsHashBackupURLs()
        testTxtPlaylistStripsSourceTagFromChannelURL()
        testTxtPlaylistReadsLeadingCommaChannelName()
        testTxtPlaylistSplitsGluedChannelsMissingNewline()
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
        testHomeLaunchPayloadUsesMovieSlugAndTVAllWindow()
        testHomeLaunchLoadFetchesDefaultSlugThenBuildsPayload()
        testRequestFailureMapsTimedOutToChinese()
        testRequestFailureMapsNSErrorTimedOutToChinese()
        testRequestFailureMapsOfflineToChinese()
        testRequestFailureKeepsAppErrorCopy()
        testHomeLaunchFirstSuccessUsesLaterSourceWhenEarlierFails()
        testHomeLaunchFirstSuccessThrowsWhenEverySourceFails()
        testHomeLaunchFirstSuccessThrowsWhenCountIsZero()
        testHomeLaunchFirstSuccessPrefersFasterSource()
        testDisplayBlurbStripsParagraphTags()
        testDisplayBlurbStripsTagsFromFallbackBlurb()
        testDisplayBlurbJoinsAdjacentParagraphsWithSpace()
        testDisplayBlurbReturnsNilWhenOnlyTagsRemain()
        testSourceRegistryDecodesDualIdAndCapabilities()
        testSourceStoreEnabledVsConfiguredAndCollectable()
        testSourceCollectorRejectsDisabledSearchCapability()
        testMacCMSSourceParserBuildsSourceMovie()
        testMergeMetadataPrefersHigherPriorityThenCompleteness()
        testSourceHealthFailureThresholdDoesNotDisable()
        testEffectivePlayScoreAppliesHealthPenalty()
        testAppDeepLinkStillUsesNumericSourceId()
        testWatchHistoryStoreUpsertsSameVideo()
        testWatchHistorySeriesKeepsOnlyLatestEpisode()
        testWatchHistorySortsByLastPlayTimeAndTrims()
        testWatchHistoryDeleteClearAndCorruptJson()
        testWatchHistoryFilePersistenceSurvivesReload()
        testWatchHistoryProgressSanitizesAndCompletesNearEnd()
        testWatchHistoryRecorderThrottlesUntilForced()
        testWatchHistoryResumeFindsEpisodeByIdThenNameThenIndex()
        testWatchHistoryDisplayCopyAndEpisodeLine()
        testEpisodePagingSplitsLongSeries()
        testAsyncTimeoutDropsLateValue()
        print("VERIFY CLIENT LOGIC PASSED")
    }
}
