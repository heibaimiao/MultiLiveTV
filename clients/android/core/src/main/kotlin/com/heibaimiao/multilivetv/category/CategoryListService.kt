package com.heibaimiao.multilivetv.category

import com.heibaimiao.multilivetv.maccms.MergeableVodItem
import com.heibaimiao.multilivetv.maccms.VodItemRaw
import com.heibaimiao.multilivetv.merge.VodMergeService
import com.heibaimiao.multilivetv.model.Source
import com.heibaimiao.multilivetv.net.VodClientException
import com.heibaimiao.multilivetv.source.SourceCapability
import com.heibaimiao.multilivetv.source.SourceCollector
import com.heibaimiao.multilivetv.source.SourceHealthStore
import com.heibaimiao.multilivetv.source.SourcePage
import com.heibaimiao.multilivetv.source.SourceStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.coroutines.coroutineContext

object CategoryListService {
    data class ListResult(
        val code: Int,
        val msg: String,
        val page: Int,
        val pageCount: Int,
        val limit: String,
        val total: Int,
        val list: List<VodMergeService.MergedVodItem>,
    )

    data class ChildListPage(
        val childId: Int,
        val list: List<VodItemRaw>,
        val pageCount: Int,
        val total: Int,
    )

    suspend fun fetchUnifiedList(
        store: SourceStore,
        slug: String?,
        page: Int,
        hours: Int? = null,
        health: SourceHealthStore = SourceHealthStore.shared,
        fetchPage: suspend (Source, Int, Int?, Int?) -> SourcePage = { source, pg, typeId, hrs ->
            SourceCollector.list(source, pg, typeId, hrs, health)
        },
    ): ListResult {
        val enabled = store.collectable(SourceCapability.CATEGORY)
        if (enabled.isEmpty()) throw VodClientException("资源站不可用")
        val sourceIds = enabled
            .sortedByDescending { store.metadataPriority(it.id) + health.healthScore(it.id) }
            .map { it.id }
        val plan = UnifiedFetchPlan.requests(slug, sourceIds)
        if (slug != null && plan.isEmpty()) {
            return ListResult(1, "ok", page, 1, "0", 0, emptyList())
        }
        val pages = fetchPlanPages(store, plan, page, hours, fetchPage)
        if (pages.isEmpty() && plan.isNotEmpty()) {
            throw VodClientException("无法连接资源站，请检查网络后重试")
        }
        val mergeable = pages.flatMap { it.first }
        val pageCount = pages.maxOfOrNull { it.second } ?: 1
        val total = pages.sumOf { it.third }
        val list = VodMergeService.sortMergedByUpdatedDesc(VodMergeService.mergeVodItems(mergeable, store))
        return ListResult(1, "ok", page, pageCount, list.size.toString(), total, list)
    }

    private suspend fun fetchPlanPages(
        store: SourceStore,
        plan: List<UnifiedFetchPlan.Request>,
        page: Int,
        hours: Int?,
        fetchPage: suspend (Source, Int, Int?, Int?) -> SourcePage,
    ): List<Triple<List<MergeableVodItem>, Int, Int>> {
        val semaphore = Semaphore(UnifiedFetchPlan.MAX_IN_FLIGHT)
        val collected = ConcurrentLinkedQueue<Triple<List<MergeableVodItem>, Int, Int>>()
        val minPages = UnifiedFetchPlan.minCompletedPages(plan)
        val isolated = SupervisorJob()
        val scope = CoroutineScope(coroutineContext + isolated)
        try {
            val jobs = plan.map { request ->
                scope.launch {
                    val source = store.byID(request.sourceId) ?: return@launch
                    val data = semaphore.withPermit {
                        withTimeoutOrNull(UnifiedFetchPlan.PER_CALL_TIMEOUT_MS) {
                            try {
                                fetchPage(source, page, request.typeId, hours)
                            } catch (error: CancellationException) {
                                throw error
                            } catch (_: Exception) {
                                null
                            }
                        }
                    } ?: return@launch
                    val items = mergeableItems(source, data)
                    if (items.isEmpty()) return@launch
                    collected += Triple(items, data.pageCount, data.total)
                }
            }
            withTimeoutOrNull(UnifiedFetchPlan.FIRST_PAINT_MS) {
                while (jobs.any { it.isActive }) {
                    delay(40)
                }
            }
            if (collected.size < minPages) {
                withTimeoutOrNull(UnifiedFetchPlan.PER_CALL_TIMEOUT_MS) {
                    while (jobs.any { it.isActive } && collected.size < minPages) {
                        delay(40)
                    }
                }
            }
            return collected.toList()
        } finally {
            isolated.cancel()
        }
    }

    private fun mergeableItems(source: Source, data: SourcePage): List<MergeableVodItem> =
        data.list.map { movie -> MergeableVodItem(movie.toVodItemRaw(), source.id, source.name) }

    suspend fun fetchVodListByTypeMerged(
        store: SourceStore,
        source: Source,
        typeId: Int?,
        page: Int,
        knownChildTypeIds: List<Int> = emptyList(),
        hours: Int? = null,
    ): ListResult {
        if (typeId == null) {
            val data = SourceCollector.list(source, page, null, hours)
            val items = data.list.map { it.toVodItemRaw() }
            return ListResult(1, "ok", data.page, data.pageCount, items.size.toString(), data.total, mergeListItems(store, source, items))
        }
        if (knownChildTypeIds.isNotEmpty()) {
            return fetchMergedChildLists(store, source, page, knownChildTypeIds, hours)
        }
        val direct = SourceCollector.list(source, page, typeId, hours)
        val directItems = direct.list.map { it.toVodItemRaw() }
        if (directItems.isNotEmpty() || direct.total > 0) {
            return ListResult(1, "ok", direct.page, direct.pageCount, directItems.size.toString(), direct.total, mergeListItems(store, source, directItems))
        }
        val types = SourceCollector.fetchTypes(source)
        val childIds = MacCMSCategoryService.getChildTypeIds(types, typeId)
        if (childIds.isEmpty()) {
            return ListResult(1, "ok", direct.page, direct.pageCount, directItems.size.toString(), direct.total, mergeListItems(store, source, directItems))
        }
        return fetchMergedChildLists(store, source, page, childIds, hours)
    }

    private suspend fun fetchMergedChildLists(
        store: SourceStore,
        source: Source,
        page: Int,
        childIds: List<Int>,
        hours: Int?,
    ): ListResult = coroutineScope {
        val semaphore = Semaphore(UnifiedFetchPlan.MAX_IN_FLIGHT)
        val pages = childIds.map { childId ->
            async {
                semaphore.withPermit {
                    val data = withTimeoutOrNull(UnifiedFetchPlan.PER_CALL_TIMEOUT_MS) {
                        runCatching { SourceCollector.list(source, page, childId, hours) }.getOrNull()
                    } ?: return@withPermit null
                    ChildListPage(childId, data.list.map { it.toVodItemRaw() }, data.pageCount, data.total)
                }
            }
        }.awaitAll().filterNotNull()
        val byId = pages.associateBy { it.childId }
        val items = mutableListOf<VodItemRaw>()
        var pageCount = 1
        var total = 0
        for (childId in childIds) {
            val child = byId[childId] ?: continue
            items += child.list
            pageCount = maxOf(pageCount, child.pageCount)
            total += child.total
        }
        val list = mergeListItems(store, source, items)
        ListResult(1, "ok", page, pageCount, list.size.toString(), total, list)
    }

    private fun mergeListItems(store: SourceStore, source: Source, items: List<VodItemRaw>) =
        VodMergeService.sortMergedByUpdatedDesc(
            VodMergeService.mergeVodItems(items.map { MergeableVodItem(it, source.id, source.name) }, store),
        )
}
