package com.heibaimiao.multilivetv.source

import com.heibaimiao.multilivetv.maccms.MacCMSClient
import com.heibaimiao.multilivetv.maccms.VodTypeRaw
import com.heibaimiao.multilivetv.model.Source
import com.heibaimiao.multilivetv.net.VodClientException

interface SourceAdapter {
    suspend fun list(source: Source, page: Int, typeId: Int?, hours: Int?): SourcePage
    suspend fun search(source: Source, keyword: String, page: Int): SourcePage
    suspend fun detail(source: Source, sourceMovieId: String): SourceMovie
    suspend fun fetchTypes(source: Source): List<VodTypeRaw>
}

object SourceAdapterRegistry {
    fun adapter(source: Source): SourceAdapter = when (source.adapter.type) {
        "cms_json" -> CMSJsonAdapter
        else -> throw VodClientException("不支持的 Adapter: ${source.adapter.type}")
    }
}

object SourceCollector {
    suspend fun list(
        source: Source,
        page: Int,
        typeId: Int?,
        hours: Int? = null,
        health: SourceHealthStore = SourceHealthStore.shared,
    ): SourcePage {
        if (!source.enabled) throw VodClientException("源不支持能力: enabled")
        if (!source.capabilities.category) throw VodClientException("源不支持能力: category")
        val adapter = SourceAdapterRegistry.adapter(source)
        return try {
            adapter.list(source, page, typeId, hours).also {
                health.recordSuccess(source.numericId)
            }
        } catch (error: Exception) {
            health.recordFailure(source.numericId)
            throw error
        }
    }

    suspend fun search(
        source: Source,
        keyword: String,
        page: Int,
        health: SourceHealthStore = SourceHealthStore.shared,
    ): SourcePage {
        if (!source.enabled) throw VodClientException("源不支持能力: enabled")
        if (!source.capabilities.search) throw VodClientException("源不支持能力: search")
        val adapter = SourceAdapterRegistry.adapter(source)
        return try {
            adapter.search(source, keyword, page).also {
                health.recordSuccess(source.numericId)
            }
        } catch (error: Exception) {
            health.recordFailure(source.numericId)
            throw error
        }
    }

    suspend fun detail(
        source: Source,
        sourceMovieId: String,
        health: SourceHealthStore = SourceHealthStore.shared,
    ): SourceMovie {
        if (!source.enabled) throw VodClientException("源不支持能力: enabled")
        if (!source.capabilities.detail) throw VodClientException("源不支持能力: detail")
        val adapter = SourceAdapterRegistry.adapter(source)
        return try {
            adapter.detail(source, sourceMovieId).also {
                health.recordSuccess(source.numericId)
            }
        } catch (error: Exception) {
            health.recordFailure(source.numericId)
            throw error
        }
    }

    suspend fun fetchTypes(source: Source): List<VodTypeRaw> {
        if (!source.enabled) throw VodClientException("源不支持能力: enabled")
        return SourceAdapterRegistry.adapter(source).fetchTypes(source)
    }
}

object CMSJsonAdapter : SourceAdapter {
    override suspend fun list(source: Source, page: Int, typeId: Int?, hours: Int?): SourcePage {
        val effectivePage = if (source.capabilities.pagination) page else 1
        val response = MacCMSClient.fetchList(source, effectivePage, typeId, hours)
        return SourcePage(
            page = response.page,
            pageCount = response.pageCount,
            total = response.total,
            list = response.list.map { MacCMSSourceParser.toSourceMovie(source, it) },
        )
    }

    override suspend fun search(source: Source, keyword: String, page: Int): SourcePage {
        val effectivePage = if (source.capabilities.pagination) page else 1
        val response = MacCMSClient.search(source, keyword, effectivePage)
        return SourcePage(
            page = response.page,
            pageCount = response.pageCount,
            total = response.total,
            list = response.list.map { MacCMSSourceParser.toSourceMovie(source, it) },
        )
    }

    override suspend fun detail(source: Source, sourceMovieId: String): SourceMovie {
        val response = MacCMSClient.fetchDetail(source, sourceMovieId)
        val raw = response.list.firstOrNull() ?: throw VodClientException("详情为空")
        return MacCMSSourceParser.toSourceMovie(source, raw)
    }

    override suspend fun fetchTypes(source: Source): List<VodTypeRaw> = MacCMSClient.fetchTypes(source)
}
