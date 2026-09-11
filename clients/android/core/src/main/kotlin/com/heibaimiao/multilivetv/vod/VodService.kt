package com.heibaimiao.multilivetv.vod

import com.heibaimiao.multilivetv.category.CategoryListService
import com.heibaimiao.multilivetv.category.CategoryMatch
import com.heibaimiao.multilivetv.category.MacCMSCategoryService
import com.heibaimiao.multilivetv.home.HomeLaunch
import com.heibaimiao.multilivetv.home.HomeLaunchPayload
import com.heibaimiao.multilivetv.maccms.MergeableVodItem
import com.heibaimiao.multilivetv.merge.VodMergeService
import com.heibaimiao.multilivetv.model.DetailResponse
import com.heibaimiao.multilivetv.model.ListResponse
import com.heibaimiao.multilivetv.model.ParseResponse
import com.heibaimiao.multilivetv.model.Source
import com.heibaimiao.multilivetv.model.TypesResponse
import com.heibaimiao.multilivetv.model.VodError
import com.heibaimiao.multilivetv.model.VodItem
import com.heibaimiao.multilivetv.model.VodVariant
import com.heibaimiao.multilivetv.net.VodClientException
import com.heibaimiao.multilivetv.parser.PlayLineWeighting
import com.heibaimiao.multilivetv.parser.PlayParser
import com.heibaimiao.multilivetv.parser.PlaybackSupport
import com.heibaimiao.multilivetv.source.SourceCapability
import com.heibaimiao.multilivetv.source.SourceCollector
import com.heibaimiao.multilivetv.source.SourceStore
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

class VodService(private val store: SourceStore = runCatching { SourceStore() }.getOrElse { SourceStore(emptyList()) }) {
    init {
        PlayLineWeighting.playPriorityBySourceId =
            store.all().associate { it.numericId to it.priority.playPriority }
    }

    suspend fun loadHomeLaunch(tvDisplay: Boolean = false): HomeLaunchPayload =
        HomeLaunch.load(
            fetchList = { slug ->
                val result = CategoryListService.fetchUnifiedList(store, slug, page = 1)
                HomeLaunch.ListPage(VodMergeService.toVodItems(result.list), result.page, result.pageCount)
            },
            tvDisplay = tvDisplay,
        )

    suspend fun fetchTypes(sourceId: Int? = null): TypesResponse {
        val source = sourceId?.let { store.byID(it) } ?: store.default()
            ?: throw VodClientException(VodError.SOURCE_NOT_FOUND.message)
        val types = SourceCollector.fetchTypes(source)
        return TypesResponse(
            source = ListResponse.SourceRef(source.id, source.name),
            categories = MacCMSCategoryService.buildCategories(types),
        )
    }

    suspend fun fetchList(page: Int, slug: String? = null, hours: Int? = null): ListResponse {
        val result = CategoryListService.fetchUnifiedList(store, slug, page, hours)
        return ListResponse(
            source = null,
            typeId = null,
            page = result.page,
            pagecount = result.pageCount,
            total = result.total,
            list = VodMergeService.toVodItems(result.list),
        )
    }

    suspend fun search(keyword: String, page: Int = 1): List<VodItem> = coroutineScope {
        val searchable = store.collectable(SourceCapability.SEARCH)
        val mergeable = searchable.map { source ->
            async {
                val pageResult = runCatching { SourceCollector.search(source, keyword, page) }.getOrNull()
                pageResult?.list.orEmpty().map {
                    MergeableVodItem(it.toVodItemRaw(), source.id, source.name)
                }
            }
        }.awaitAll().flatten()
        val merged = VodMergeService.sortMergedByUpdatedDesc(
            VodMergeService.mergeVodItems(mergeable, store),
        )
        CategoryMatch.excludingHidden(VodMergeService.toVodItems(merged))
    }

    suspend fun detail(
        sourceId: Int,
        vodId: String,
        knownVariants: List<VodVariant> = emptyList(),
        onPrimary: ((DetailResponse) -> Unit)? = null,
    ): DetailResponse {
        val source = store.byID(sourceId) ?: throw VodClientException(VodError.SOURCE_NOT_FOUND.message)
        val fetched = VodMergeService.fetchPrimaryVodDetail(source, vodId)
            ?: throw VodClientException(VodError.VOD_NOT_FOUND.message)
        onPrimary?.invoke(fetched.second)
        return VodMergeService.enrichMergedVodDetail(
            store = store,
            source = source,
            vodId = vodId,
            primary = fetched.first,
            knownVariants = knownVariants,
        )
    }

    suspend fun parsePlay(sourceId: Int, url: String): ParseResponse {
        val source = store.byID(sourceId) ?: throw VodClientException(VodError.SOURCE_NOT_FOUND.message)
        val response = PlayParser.parsePlayAddress(source, url)
        return if (PlaybackSupport.isDirectMediaURL(response.url)) response else ParseResponse(response.url, parsed = false)
    }

    fun source(id: Int): Source? = store.byID(id)
}
