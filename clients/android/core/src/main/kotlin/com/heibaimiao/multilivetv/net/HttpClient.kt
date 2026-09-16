package com.heibaimiao.multilivetv.net

import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

object HttpClient {
    val okHttp: OkHttpClient = OkHttpClient.Builder()
        .dns(ResilientDns)
        .dispatcher(
            okhttp3.Dispatcher().apply {
                maxRequests = 12
                maxRequestsPerHost = 4
            },
        )
        .connectTimeout(NetworkConfig.CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .readTimeout(NetworkConfig.REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .callTimeout(NetworkConfig.REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    fun get(
        url: String,
        extraHeaders: Map<String, String> = emptyMap(),
        extraQuery: Map<String, String> = emptyMap(),
        range: String? = null,
    ): HttpResponse {
        val httpUrl = buildUrl(url, extraQuery)
        val request = Request.Builder()
            .url(httpUrl)
            .header("User-Agent", NetworkConfig.USER_AGENT)
            .apply {
                extraHeaders.forEach { (key, value) -> header(key, value) }
                if (range != null) header("Range", range)
            }
            .build()
        okHttp.newCall(request).execute().use { response ->
            val body = response.body?.bytes() ?: ByteArray(0)
            return HttpResponse(
                code = response.code,
                contentType = response.header("Content-Type").orEmpty(),
                body = body,
            )
        }
    }

    fun getOrThrow(
        url: String,
        extraHeaders: Map<String, String> = emptyMap(),
        extraQuery: Map<String, String> = emptyMap(),
    ): HttpResponse {
        val response = get(url, extraHeaders, extraQuery)
        if (response.code !in 200..299) {
            throw VodClientException("HTTP ${response.code}")
        }
        return response
    }

    private fun buildUrl(base: String, extraQuery: Map<String, String>): okhttp3.HttpUrl {
        val normalized = if (extraQuery.isEmpty() || base.contains("?")) {
            base
        } else if (base.endsWith("/")) {
            base
        } else {
            "$base/"
        }
        val builder = normalized.toHttpUrl().newBuilder()
        extraQuery.forEach { (key, value) -> builder.addQueryParameter(key, value) }
        return builder.build()
    }
}

data class HttpResponse(
    val code: Int,
    val contentType: String,
    val body: ByteArray,
) {
    fun text(): String = body.toString(Charsets.UTF_8).removePrefix("\uFEFF").trim()
}
