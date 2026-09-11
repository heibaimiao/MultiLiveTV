package com.heibaimiao.multilivetv.maccms

import com.heibaimiao.multilivetv.model.Source
import com.heibaimiao.multilivetv.net.HttpClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject

object MacCMSClient {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    fun catalogParams(page: Int, typeId: Int?, hours: Int? = null): Map<String, String> {
        val params = mutableMapOf("ac" to "detail", "pg" to page.toString())
        if (typeId != null) params["t"] = typeId.toString()
        if (hours != null && hours > 0) params["h"] = hours.toString()
        return params
    }

    fun searchParams(keyword: String, page: Int): Map<String, String> = mapOf(
        "ac" to "detail",
        "wd" to keyword,
        "pg" to page.toString(),
    )

    suspend fun fetchTypes(source: Source): List<VodTypeRaw> = withContext(Dispatchers.IO) {
        parseList(source.url, mapOf("ac" to "list", "pg" to "1")).types
    }

    suspend fun fetchList(
        source: Source,
        page: Int,
        typeId: Int?,
        hours: Int? = null,
    ): MacCMSListResponse = withContext(Dispatchers.IO) {
        parseList(source.url, catalogParams(page, typeId, hours))
    }

    suspend fun fetchDetail(source: Source, ids: String): MacCMSDetailResponse = withContext(Dispatchers.IO) {
        val text = HttpClient.getOrThrow(source.url, extraQuery = mapOf("ac" to "detail", "ids" to ids)).text()
        MacCMSJsonParser.parseDetail(json.parseToJsonElement(text).jsonObject)
    }

    suspend fun search(source: Source, keyword: String, page: Int): MacCMSListResponse =
        withContext(Dispatchers.IO) {
            parseList(source.url, searchParams(keyword, page))
        }

    private fun parseList(baseUrl: String, params: Map<String, String>): MacCMSListResponse {
        val text = HttpClient.getOrThrow(baseUrl, extraQuery = params).text()
        return MacCMSJsonParser.parseList(json.parseToJsonElement(text).jsonObject)
    }
}
