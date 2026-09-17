package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.category.CategoryMatch
import com.heibaimiao.multilivetv.category.CategoryTree
import com.heibaimiao.multilivetv.category.CategoryTreeBuilder
import com.heibaimiao.multilivetv.category.SlugCategory
import com.heibaimiao.multilivetv.category.UnifiedCategories
import com.heibaimiao.multilivetv.category.UnifiedFetchPlan
import com.heibaimiao.multilivetv.home.HomeFeed
import com.heibaimiao.multilivetv.maccms.MacCMSJsonParser
import com.heibaimiao.multilivetv.maccms.MergeableVodItem
import com.heibaimiao.multilivetv.maccms.VodItemRaw
import com.heibaimiao.multilivetv.merge.VodMergeService
import com.heibaimiao.multilivetv.model.Episode
import com.heibaimiao.multilivetv.model.PlaySource
import com.heibaimiao.multilivetv.model.Source
import com.heibaimiao.multilivetv.model.VodItem
import com.heibaimiao.multilivetv.model.VodVariant
import com.heibaimiao.multilivetv.parser.PlayLineWeighting
import com.heibaimiao.multilivetv.parser.PlaybackSeek
import com.heibaimiao.multilivetv.parser.PlaybackSupport
import com.heibaimiao.multilivetv.parser.PlayParser
import com.heibaimiao.multilivetv.parser.VodPlaybackFailover
import com.heibaimiao.multilivetv.source.SourceStore
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ClientLogicTest {
    private fun vod(
        id: String,
        name: String,
        time: Int = 0,
        typeName: String? = null,
        vodClass: String? = null,
        year: String? = null,
    ) = VodItem(id, name, "", typeName = typeName, vodClass = vodClass, vodYear = year, vodTime = time)

    private fun raw(id: String, name: String, year: String = "", time: Int = 0) = VodItemRaw(
        vodId = id, vodName = name, vodPic = "", vodRemarks = "", vodYear = year, vodArea = "",
        vodClass = "", vodBlurb = "", vodContent = "", vodPlayFrom = "", vodPlayURL = "",
        typeId = 0, typeName = "", vodTime = time,
    )

    private fun source(id: Int, name: String, enabled: Boolean = true) = Source.legacy(
        id, name, "https://example.com/$id/", flag = if (enabled) 0 else 1,
    )

    @Test
    fun sourceStoreDropsDisabledAndVip() {
        val store = SourceStore(
            listOf(
                Source.legacy(1, "A", "https://a/", flag = 0),
                Source.legacy(2, "B", "https://b/", flag = 1),
                Source.legacy(3, "C", "https://c/", flag = 0, vipOnly = true),
            ),
        )
        assertEquals(listOf(1), store.enabled().map { it.id })
        assertEquals(1, store.default()?.id)
        assertEquals(null, store.byID(2))
    }

    @Test
    fun sourceStoreKeepsLastDuplicateNumericId() {
        val store = SourceStore(
            listOf(
                Source.legacy(33, "旧", "https://old/"),
                Source.legacy(33, "新", "https://new/"),
            ),
        )
        assertEquals("新", store.configured(33)?.name)
    }

    @Test
    fun bundledRegistryLoads() {
        val store = SourceStore()
        assertTrue(store.enabled().isNotEmpty())
        assertTrue(store.enabled().none { it.vipOnly == true })
    }

    @Test
    fun mergeIntoPoolPreservesIncomingOrder() {
        val incoming = (1..5).map { vod("id-$it", "片名$it", time = 100 - it) }
        val names = HomeFeed.mergeIntoPool(emptyList(), incoming, isFirstBatch = true).map { it.vodName }
        assertEquals(incoming.map { it.vodName }, names)
    }

    @Test
    fun mergeKeyKeepsHomonymousFilmsWithDifferentYears() {
        val hk = vod("1", "兄弟", typeName = "动作片", year = "2007")
        val us = vod("2", "兄弟", typeName = "剧情片", year = "2009")
        val merged = HomeFeed.mergeIntoPool(emptyList(), listOf(hk, us), isFirstBatch = true)
        assertEquals(setOf("1", "2"), merged.map { it.vodId }.toSet())
        assertEquals(listOf("2", "1"), merged.map { it.vodId })
    }

    @Test
    fun mergeKeyStillCollapsesSameTitleAndYear() {
        val merged = HomeFeed.mergeIntoPool(
            emptyList(),
            listOf(vod("1", "兄弟", year = "2009"), vod("2", "兄弟", year = "2009")),
            isFirstBatch = true,
        )
        assertEquals(listOf("2"), merged.map { it.vodId })
    }

    @Test
    fun mergeKeyTreatsYearSuffixAsTheSameYear() {
        val a = vod("1", "兄弟", year = "2009年")
        val b = vod("2", "兄弟", year = "2009")
        assertEquals(HomeFeed.mergeKey(a), HomeFeed.mergeKey(b))
    }

    @Test
    fun vodMergeKeepsHomonymousFilmsWithDifferentYears() {
        val store = SourceStore(listOf(source(1, "A")))
        val items = listOf(
            MergeableVodItem(raw("1", "兄弟", year = "2007"), 1, "A"),
            MergeableVodItem(raw("2", "兄弟", year = "2009"), 1, "A"),
        )
        val merged = VodMergeService.toVodItems(VodMergeService.mergeVodItems(items, store))
        assertEquals(listOf("1", "2"), merged.map { it.vodId })
    }

    @Test
    fun unifiedMergeSortsByVodTimeDesc() {
        val store = SourceStore(listOf(source(1, "A"), source(2, "B")))
        val items = listOf(
            MergeableVodItem(raw("1", "旧片", time = 100), 1, "A"),
            MergeableVodItem(raw("2", "新片", time = 300), 1, "A"),
            MergeableVodItem(raw("3", "新片", time = 200), 2, "B"),
        )
        val merged = VodMergeService.sortMergedByUpdatedDesc(VodMergeService.mergeVodItems(items, store))
        assertEquals(listOf("新片", "旧片"), merged.map { it.item.vodName })
        assertEquals(300, merged[0].item.vodTime)
    }

    @Test
    fun mergeFoldsEmptyYearIntoConcreteYear() {
        val store = SourceStore(listOf(source(1, "A"), source(2, "B")))
        val items = listOf(
            MergeableVodItem(raw("1", "热血部落", year = "", time = 100), 1, "A"),
            MergeableVodItem(raw("2", "热血部落", year = "2024", time = 200), 2, "B"),
        )
        val merged = VodMergeService.mergeVodItems(items, store)
        assertEquals(1, merged.size)
        assertEquals(200, merged[0].item.vodTime)
        assertEquals(2, merged[0].variants.size)
    }

    @Test
    fun sortPrefersReleaseYearOverUpdateTime() {
        val olderFilm = vod("1", "老片", time = 999, year = "1999")
        val newerFilm = vod("2", "新片", time = 1, year = "2024")
        assertEquals(listOf("新片", "老片"), HomeFeed.sortByUpdatedDesc(listOf(olderFilm, newerFilm)).map { it.vodName })
    }

    @Test
    fun sortPutsMissingYearLast() {
        val pool = listOf(
            vod("1", "旧片新更", time = 900, year = "2020"),
            vod("2", "新片旧更", time = 100, year = "2026"),
            vod("3", "无年份", time = 999),
        )
        assertEquals(listOf("2", "1", "3"), HomeFeed.sortByUpdatedDesc(pool).map { it.vodId })
    }

    @Test
    fun normalizeYearRejectsFuturePlaceholder() {
        assertEquals("", HomeFeed.normalizeYear("2030"))
        assertEquals("", HomeFeed.normalizeYear("1899"))
        val current = HomeFeed.currentCalendarYear()
        assertEquals(current.toString(), HomeFeed.normalizeYear(current.toString()))
        assertEquals((current + 1).toString(), HomeFeed.normalizeYear((current + 1).toString()))
        assertEquals("", HomeFeed.normalizeYear((current + 2).toString()))
    }

    @Test
    fun futurePlaceholderKeepsRecentFilmsNearTop() {
        val recent = vod("1", "热血部落", time = 1_700_000_000, year = "2030")
        val older = vod("2", "老片", time = 1_600_000_000, year = "2020")
        assertEquals(HomeFeed.currentCalendarYear(), HomeFeed.sortYearValue("2030", 1_700_000_000))
        assertEquals(listOf("1", "2"), HomeFeed.sortByUpdatedDesc(listOf(older, recent)).map { it.vodId })
    }

    @Test
    fun categoryMatchHidesEthicalTitles() {
        val tree = UnifiedCategories.tree()
        val items = listOf(
            vod("1", "正常", typeName = "动作片"),
            vod("2", "隐藏", typeName = "伦理片"),
        )
        val filtered = CategoryMatch.filter(items, "movie", tree)
        assertTrue(filtered.none { it.vodName == "隐藏" })
    }

    @Test
    fun iPadMovieGridDoesNotShowEthicalUnderMovieAll() {
        val tree = CategoryTreeBuilder.build(UnifiedCategories.bundled)
        val items = listOf(
            vod("1", "正常电影", typeName = "动作片", year = "2024"),
            vod("2", "伦理标题", typeName = "伦理片", year = "2024"),
        )
        val filtered = CategoryMatch.filter(items, "movie", tree)
        assertEquals(listOf("正常电影"), filtered.map { it.vodName })
    }

    @Test
    fun playbackSupportRejectsJiexiHosts() {
        assertFalse(PlaybackSupport.isDirectMediaURL("https://jx.m3u8.tv/jiexi.php?url=http://a.com/1.m3u8"))
        assertTrue(PlaybackSupport.isDirectMediaURL("https://cdn.example.com/index.m3u8"))
        assertTrue(PlaybackSupport.isDirectMediaURL("https://cdn.example.com/a.mp4"))
    }

    @Test
    fun playParserSplitsLinesAndEpisodes() {
        val sources = PlayParser.parsePlayURL(
            "wjm3u8\$\$\$mym3u8",
            "第1集\$https://a.com/1.m3u8#第2集\$https://a.com/2.m3u8\$\$\$HD\$https://b.com/1.m3u8",
        )
        assertEquals(listOf("无尽", "猫眼"), sources.map { it.name })
        assertEquals(2, sources[0].episodes.size)
        assertEquals("第1集", sources[0].episodes[0].name)
    }

    @Test
    fun maccmsParserReadsFlexibleIdsAndTime() {
        val json = Json.parseToJsonElement(
            """{"code":1,"list":[{"vod_id":12,"vod_name":"测","vod_time":"2024-01-02 03:04:05"}]}""",
        ).jsonObject
        val parsed = MacCMSJsonParser.parseList(json)
        assertEquals("12", parsed.list[0].vodId)
        assertTrue(parsed.list[0].vodTime > 0)
    }

    @Test
    fun unifiedCategoriesDefaultMovie() {
        val tree: CategoryTree = UnifiedCategories.tree()
        assertEquals("movie", CategoryTreeBuilder.defaultSlug(tree))
        assertTrue(tree.primary.any { it.label == "电影" })
        val children: List<SlugCategory> = tree.childrenByParent["tv"].orEmpty()
        assertTrue(children.isNotEmpty())
    }

    @Test
    fun parentAllUsesChildTypeIdsNotEmptyParent() {
        val ids = UnifiedCategories.listTypeIds("movie", 33)
        assertTrue(ids.isNotEmpty())
        assertFalse(1 in ids)
        assertTrue(5 in ids)
        assertTrue(6 in ids)
    }

    @Test
    fun leafCategoryKeepsSingleTypeId() {
        assertEquals(listOf(5), UnifiedCategories.listTypeIds("movie-action", 33))
    }

    @Test
    fun parentAllPlanUsesTwoSourcesAndChildTypes() {
        val sourceIds = listOf(33, 125, 143, 146, 157, 158, 159, 160)
        val plan = UnifiedFetchPlan.requests("movie", sourceIds)
        assertEquals(setOf(33, 125), plan.map { it.sourceId }.toSet())
        assertTrue(plan.none { it.typeId == 1 })
        assertTrue(plan.any { it.sourceId == 33 && it.typeId == 5 })
        assertTrue(plan.size > 2)
    }

    @Test
    fun leafPlanKeepsOneRequestPerSource() {
        val sourceIds = listOf(33, 125, 143, 146, 157, 158, 159, 160, 161)
        val plan = UnifiedFetchPlan.requests("movie-action", sourceIds)
        assertEquals(3, UnifiedFetchPlan.LEAF_SOURCE_LIMIT)
        assertEquals(UnifiedFetchPlan.LEAF_SOURCE_LIMIT, plan.size)
        assertEquals(plan.size, plan.map { it.sourceId }.toSet().size)
        assertTrue(plan.all { it.typeId != null })
        assertEquals(1, UnifiedFetchPlan.minCompletedPages(plan))
    }

    @Test
    fun parentPlanWaitsForTwoPagesNotFourSources() {
        val plan = UnifiedFetchPlan.requests("movie", listOf(33, 125, 143, 146))
        assertTrue(plan.size > 2)
        assertEquals(2, UnifiedFetchPlan.minCompletedPages(plan))
    }

    @Test
    fun screenDragMapsFullWidthToFullDuration() {
        assertEquals(60_000L, PlaybackSeek.targetFromDrag(0L, 60_000L, dragPx = 200f, widthPx = 200f))
        assertEquals(0L, PlaybackSeek.targetFromDrag(0L, 60_000L, dragPx = 0f, widthPx = 200f))
        assertEquals(30_000L, PlaybackSeek.targetFromDrag(0L, 60_000L, dragPx = 100f, widthPx = 200f))
    }

    @Test
    fun screenDragClampsAndHandlesBadWidth() {
        assertEquals(60_000L, PlaybackSeek.targetFromDrag(50_000L, 60_000L, dragPx = 400f, widthPx = 200f))
        assertEquals(0L, PlaybackSeek.targetFromDrag(5_000L, 60_000L, dragPx = -400f, widthPx = 200f))
        assertEquals(12_000L, PlaybackSeek.targetFromDrag(12_000L, 60_000L, dragPx = 40f, widthPx = 0f))
    }

    @Test
    fun doubleTapEdgesSeekCenterToggles() {
        assertEquals(PlaybackSeek.TapZone.Rewind, PlaybackSeek.tapZone(20f, 300f))
        assertEquals(PlaybackSeek.TapZone.Forward, PlaybackSeek.tapZone(280f, 300f))
        assertEquals(PlaybackSeek.TapZone.Center, PlaybackSeek.tapZone(150f, 300f))
        assertEquals(0L, PlaybackSeek.doubleTapTarget(5_000L, 60_000L, PlaybackSeek.TapZone.Rewind))
        assertEquals(15_000L, PlaybackSeek.doubleTapTarget(5_000L, 60_000L, PlaybackSeek.TapZone.Forward))
        assertEquals(null, PlaybackSeek.doubleTapTarget(5_000L, 60_000L, PlaybackSeek.TapZone.Center))
    }

    @Test
    fun playLinesRankHongniuBeforeWuyouAndSkipSharePages() {
        val lines = PlayLineWeighting.forDetailDisplay(
            listOf(
                PlaySource("无忧", "ws", listOf(Episode("1", "https://cdn.example/ws.m3u8")), 33, playFrom = "wsym3u8"),
                PlaySource("红牛", "hn", listOf(Episode("1", "https://cdn.example/hn.m3u8")), 164, playFrom = "hnm3u8"),
                PlaySource("分享", "share", listOf(Episode("1", "https://vod.example/share/abc")), 33, playFrom = "share"),
            ),
        )
        assertEquals(listOf("hn", "ws", "share"), lines.map { it.key })
        assertEquals(920, lines[0].weight)
        assertEquals(790, lines[1].weight)
        assertEquals(0, PlayLineWeighting.preferredPlayableIndex(lines))
        assertEquals("hn", lines[PlayLineWeighting.preferredPlayableIndex(lines)].key)
    }

    @Test
    fun playLineFailoverStartsWithSelectedThenWeightedDirectBackups() {
        val ranked = PlayLineWeighting.forDetailDisplay(
            listOf(
                PlaySource("无尽", "wj", listOf(Episode("正片", "https://cdn.example/wj.m3u8")), 33, playFrom = "wjm3u8"),
                PlaySource("红牛", "hn", listOf(Episode("正片", "https://cdn.example/hn.m3u8")), 164, playFrom = "hnm3u8"),
                PlaySource("非凡", "ff", listOf(Episode("正片", "https://cdn.example/ff.m3u8")), 159, playFrom = "ffm3u8"),
                PlaySource("网页", "html", listOf(Episode("正片", "https://v.qq.com/x/cover/a.html")), 901, playFrom = "qq"),
            ),
        )
        assertEquals(listOf("html", "hn", "wj", "ff"), ranked.map { it.key })
        assertEquals("hn", ranked[PlayLineWeighting.preferredPlayableIndex(ranked)].key)
        val selected = ranked.indexOfFirst { it.key == "wj" }
        val candidates = VodPlaybackFailover.candidates(
            playSources = ranked,
            selectedIndex = selected,
            episode = ranked[selected].episodes.first(),
            fallbackSourceId = 33,
        )
        assertEquals(
            listOf("https://cdn.example/wj.m3u8", "https://cdn.example/hn.m3u8", "https://cdn.example/ff.m3u8"),
            candidates.map { it.episode.url },
        )
        assertEquals(null, VodPlaybackFailover.nextIndex(2, 3))
        assertEquals(1, VodPlaybackFailover.nextIndex(0, 3))
    }

    @Test
    fun matchTitleIgnoresTrailingYearInName() {
        assertEquals("所爱之人", HomeFeed.titleKeyForMatch("所爱之人2026"))
        assertEquals("所爱之人", HomeFeed.titleKeyForMatch("所爱之人 2026"))
        assertEquals("所爱之人", HomeFeed.searchKeyword("所爱之人2026"))
        assertTrue(
            VodMergeService.isCompatibleVodMatch(
                raw("1", "所爱之人2026", year = "2026"),
                raw("2", "所爱之人", year = "2026"),
            ),
        )
        assertFalse(
            VodMergeService.isCompatibleVodMatch(
                raw("1", "兄弟2007", year = "2007"),
                raw("2", "兄弟2009", year = "2009"),
            ),
        )
    }

    @Test
    fun enrichPlanUsesKnownVariantsAndLimitsSearch() {
        val known = listOf(
            VodVariant(160, "量子", "99"),
            VodVariant(33, "无忧", "11"),
        )
        val searchable = listOf(33, 125, 143, 146, 157, 158, 159, 160, 161)
        val plan = VodMergeService.enrichPlan(
            primarySourceId = 160,
            primaryVodId = "99",
            knownVariants = known,
            searchableSourceIds = searchable,
        )
        assertEquals(setOf("160:99", "33:11"), plan.known.map { "${it.sourceId}:${it.vodId}" }.toSet())
        assertEquals(listOf(125, 143, 146, 157, 158, 159), plan.searchSourceIds)
        assertEquals(VodMergeService.SEARCH_SOURCE_LIMIT, plan.searchSourceIds.size)
    }

    @Test
    fun enrichPlanSkipsSearchWhenEnoughVariantsKnown() {
        val known = (1..6).map { VodVariant(it, "S$it", "$it") }
        val plan = VodMergeService.enrichPlan(
            primarySourceId = 1,
            primaryVodId = "1",
            knownVariants = known,
            searchableSourceIds = (1..20).toList(),
        )
        assertTrue(plan.searchSourceIds.isEmpty())
        assertEquals(6, plan.known.map { it.sourceId }.toSet().size)
    }
}
