package com.heibaimiao.multilivetv.parser

import com.heibaimiao.multilivetv.maccms.VodItemRaw
import com.heibaimiao.multilivetv.model.Episode
import com.heibaimiao.multilivetv.model.ParseResponse
import com.heibaimiao.multilivetv.model.PlaySource
import com.heibaimiao.multilivetv.model.Source
import com.heibaimiao.multilivetv.net.HttpClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.URI
import java.net.URLEncoder

object PlayParser {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    private val playSourceNames = mapOf(
        "wjm3u8" to "无尽", "snm3u8" to "索尼", "ikm3u8" to "爱酷", "ffm3u8" to "非凡",
        "feifan" to "非凡", "gsm3u8" to "光速", "gsyun" to "光速", "mtm3u8" to "茅台",
        "mtyun" to "茅台", "mym3u8" to "猫眼", "hym3u8" to "虎牙直链", "hyyun" to "虎牙云",
        "modum3u8" to "魔都", "liangzi" to "量子", "jsyun" to "极速", "subyun" to "速播",
        "lzm3u8" to "量子", "jpm3u8" to "极品", "jsm3u8" to "极速", "subm3u8" to "速播",
        "bfzym3u8" to "暴风", "hnm3u8" to "红牛", "hnyun" to "红牛", "bjm3u8" to "八戒",
        "wolong" to "卧龙", "maotai" to "茅台", "maoyan" to "猫眼", "kcm3u8" to "快车",
        "xlm3u8" to "新浪", "dbm3u8" to "豆瓣", "hkm3u8" to "华为", "yym3u8" to "丫丫",
        "ckm3u8" to "CK", "dym3u8" to "电影", "ukm3u8" to "UK", "lsm3u8" to "乐视",
        "qhm3u8" to "奇虎", "ysm3u8" to "影视", "huyam3u8" to "虎牙", "tpm3u8" to "淘片",
        "tkm3u8" to "天空", "1080zyk" to "1080看", "zuidam3u8" to "最大", "kuaikan" to "快看",
    )

    private val playSourcePrefixNames = mapOf(
        "wj" to "无尽", "sn" to "索尼", "ik" to "爱酷", "lz" to "量子", "ff" to "非凡",
        "gs" to "光速", "mt" to "茅台", "my" to "猫眼", "hy" to "虎牙", "modu" to "魔都",
        "jp" to "极品", "js" to "极速", "sub" to "速播", "bfzy" to "暴风", "hn" to "红牛",
        "bj" to "八戒", "kc" to "快车", "xl" to "新浪", "db" to "豆瓣", "hk" to "华为",
        "yy" to "丫丫", "ck" to "CK", "dy" to "电影", "uk" to "UK", "ls" to "乐视",
        "qh" to "奇虎", "ys" to "影视", "tp" to "淘片", "tk" to "天空", "wolong" to "卧龙",
        "feifan" to "非凡", "maotai" to "茅台", "maoyan" to "猫眼", "gsyun" to "光速",
        "mtyun" to "茅台", "hyyun" to "虎牙云", "liangzi" to "量子", "jsyun" to "极速", "subyun" to "速播",
    )

    private val m3u8Pattern = Regex("""https?://[^\s"'<>]+\.m3u8[^\s"'<>]*""", RegexOption.IGNORE_CASE)
    private val iframePlayerPattern = Regex("""src="([^"]*playm3u8\.php\?url=[^"]+)"""", RegexOption.IGNORE_CASE)

    data class VodWithSource(val source: Source, val vod: VodItemRaw)

    fun parsePlayURL(vodPlayFrom: String, vodPlayURL: String): List<PlaySource> {
        if (vodPlayFrom.isEmpty() || vodPlayURL.isEmpty()) return emptyList()
        val fromList = splitPlayFrom(vodPlayFrom)
        val urlList = if (vodPlayURL.contains("$$$")) vodPlayURL.split("$$$") else listOf(vodPlayURL)
        return fromList.mapIndexed { index, name ->
            val rawEpisodes = urlList.getOrNull(index) ?: urlList.firstOrNull().orEmpty()
            val episodes = rawEpisodes.split("#").mapNotNull { segment ->
                if (segment.isEmpty()) return@mapNotNull null
                val dollar = segment.indexOf('$')
                if (dollar >= 0) {
                    val epName = segment.substring(0, dollar).ifEmpty { "播放" }
                    val url = segment.substring(dollar + 1).trim()
                    if (url.isEmpty()) null else Episode(epName, url)
                } else {
                    Episode("第$segment", segment)
                }
            }
            var key = name.trim()
            if (key.isEmpty()) key = "line-${index + 1}"
            PlayLineWeighting.annotate(
                PlaySource(
                    name = formatPlaySourceName(name, index),
                    key = key,
                    episodes = episodes,
                    playFrom = key,
                ),
                rawPlayFrom = key,
            )
        }
    }

    fun mergePlaySources(entries: List<VodWithSource>): List<PlaySource> {
        data class Ranked(val playSource: PlaySource)
        val merged = linkedMapOf<String, Ranked>()
        for (entry in entries) {
            val parsed = parsePlayURL(entry.vod.vodPlayFrom, entry.vod.vodPlayURL)
            for (line in parsed) {
                val playFrom = line.playFrom ?: line.key
                val mergeKey = "${entry.source.id}:${line.name}"
                val ranked = Ranked(
                    PlayLineWeighting.annotate(
                        PlaySource(
                            name = displayPlaySourceName(entry.source.name, line.name),
                            key = mergeKey,
                            episodes = line.episodes,
                            sourceId = entry.source.id,
                            playFrom = playFrom,
                        ),
                        rawPlayFrom = playFrom,
                    ),
                )
                val existing = merged[mergeKey]
                if (existing != null && !shouldReplace(existing.playSource, ranked.playSource)) continue
                merged[mergeKey] = ranked
            }
        }
        return PlayLineWeighting.sort(merged.values.map { it.playSource })
    }

    fun displayPlaySourceName(sourceName: String, lineName: String): String {
        val source = sourceName.trim()
        val line = lineName.trim()
        if (source.isEmpty()) return line
        if (line.isEmpty() || source == line) return source
        if (line.startsWith(source)) return line
        return "$source · $line"
    }

    suspend fun parsePlayAddress(source: Source, playURL: String): ParseResponse = withContext(Dispatchers.IO) {
        val trimmed = playURL.trim()
        if (trimmed.isEmpty()) return@withContext ParseResponse(playURL, parsed = false)
        if (PlaybackSupport.isDirectMediaURL(trimmed)) {
            return@withContext ParseResponse(trimmed, parsed = true)
        }
        runCatching { resolveFromOriginalPlayPage(source, trimmed) }.getOrNull()?.let {
            return@withContext ParseResponse(it, parsed = true)
        }
        val jxURL = source.jxUrl
        if (jxURL.isNullOrEmpty()) return@withContext ParseResponse(trimmed, parsed = false)
        val encoded = URLEncoder.encode(trimmed, Charsets.UTF_8.name()).replace("+", "%20")
        val resolved = runCatching { resolveFromJXEndpoint(jxURL + encoded, trimmed) }.getOrNull()
        if (resolved != null) ParseResponse(resolved, parsed = true) else ParseResponse(trimmed, parsed = false)
    }

    private fun resolveFromOriginalPlayPage(source: Source, playURL: String): String? {
        val headers = PlaybackSupport.httpHeaders(source, playURL)
        val response = HttpClient.get(playURL, extraHeaders = headers, range = "bytes=0-16383")
        if (response.code !in 200..299) return null
        if (response.contentType.contains("application/json")) {
            parseJSONPlaybackURL(response.text())?.let {
                if (PlaybackSupport.isDirectMediaURL(it)) return it
            }
        }
        extractDirectMediaURL(response.text())?.let {
            if (PlaybackSupport.isDirectMediaURL(it)) return it
        }
        return null
    }

    private fun resolveFromJXEndpoint(url: String, originalURL: String): String? {
        val response = HttpClient.get(url)
        if (response.code !in 200..299) return null
        if (response.contentType.contains("application/json")) {
            parseJSONPlaybackURL(response.text())?.let {
                if (PlaybackSupport.isDirectMediaURL(it)) return it
            }
        }
        val text = response.text()
        if (text.startsWith("http")) {
            sanitizePlaybackURL(text.split(Regex("""\s+""")).firstOrNull())?.let {
                if (PlaybackSupport.isDirectMediaURL(it)) return it
            }
        }
        firstM3U8(text)?.let { if (PlaybackSupport.isDirectMediaURL(it)) return it }
        firstIframePlayerPath(text)?.let { iframePath ->
            val playerURL = absoluteJXURL(iframePath, url) ?: return@let
            val player = HttpClient.get(playerURL)
            if (player.code !in 200..299) return@let
            if (player.contentType.contains("application/json")) {
                parseJSONPlaybackURL(player.text())?.let {
                    if (PlaybackSupport.isDirectMediaURL(it)) return it
                }
            }
            val playerText = player.text()
            firstM3U8(playerText)?.let { if (PlaybackSupport.isDirectMediaURL(it)) return it }
            if (playerText.startsWith("http")) {
                sanitizePlaybackURL(playerText.split(Regex("""\s+""")).firstOrNull())?.let {
                    if (PlaybackSupport.isDirectMediaURL(it)) return it
                }
            }
        }
        return if (PlaybackSupport.isDirectMediaURL(originalURL)) originalURL else null
    }

    private fun parseJSONPlaybackURL(text: String): String? {
        val element = runCatching { json.parseToJsonElement(text) }.getOrNull() ?: return null
        if (element is JsonPrimitive) return sanitizePlaybackURL(element.content)
        val dict = element as? JsonObject ?: return null
        dict["url"]?.jsonPrimitive?.contentOrNull?.let { return sanitizePlaybackURL(it) }
        dict["data"]?.let { data ->
            if (data is JsonObject) {
                data["url"]?.jsonPrimitive?.contentOrNull?.let { return sanitizePlaybackURL(it) }
            }
        }
        return null
    }

    fun extractDirectMediaURL(text: String): String? = firstM3U8(text)

    private fun firstM3U8(text: String): String? =
        sanitizePlaybackURL(m3u8Pattern.find(text)?.value)

    private fun firstIframePlayerPath(text: String): String? =
        iframePlayerPattern.find(text)?.groupValues?.getOrNull(1)?.replace("&amp;", "&")

    private fun absoluteJXURL(path: String, base: String): String? {
        if (path.startsWith("http")) return path
        val uri = runCatching { URI(base) }.getOrNull() ?: return null
        val origin = "${uri.scheme}://${uri.authority}"
        return origin.trimEnd('/') + "/" + path.trimStart('/')
    }

    private fun sanitizePlaybackURL(raw: String?): String? {
        var value = raw?.trim()?.removePrefix("\uFEFF").orEmpty()
        if (value.isEmpty() || !value.startsWith("http")) return null
        return value
    }

    private fun splitPlayFrom(vodPlayFrom: String): List<String> = when {
        vodPlayFrom.isEmpty() -> emptyList()
        vodPlayFrom.contains("$$$") -> vodPlayFrom.split("$$$").filter { it.isNotEmpty() }
        vodPlayFrom.contains(",") -> vodPlayFrom.split(",").filter { it.isNotEmpty() }
        else -> listOf(vodPlayFrom)
    }

    private fun shouldReplace(existing: PlaySource, incoming: PlaySource): Boolean {
        val incomingScore = incoming.episodes.count { PlaybackSupport.isDirectMediaURL(it.url) }
        val existingScore = existing.episodes.count { PlaybackSupport.isDirectMediaURL(it.url) }
        if (incomingScore != existingScore) return incomingScore > existingScore
        return incoming.episodes.size > existing.episodes.size
    }

    private fun formatPlaySourceName(raw: String, index: Int): String {
        val key = raw.trim().lowercase()
        if (key.isEmpty()) return "线路${index + 1}"
        playSourceNames[key]?.let { return it }
        var prefix = key
        if (prefix.endsWith("m3u8")) prefix = prefix.dropLast(4)
        if (prefix.endsWith("yun")) prefix = prefix.dropLast(3)
        playSourcePrefixNames[prefix]?.let { return it }
        if (raw.matches(Regex("""^线路\d+$""", RegexOption.IGNORE_CASE))) return raw.trim()
        return "线路${index + 1}"
    }
}
