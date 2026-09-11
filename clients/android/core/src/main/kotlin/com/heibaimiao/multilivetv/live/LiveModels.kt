package com.heibaimiao.multilivetv.live

import com.heibaimiao.multilivetv.net.RemoteMediaURL
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

@Serializable
data class LiveSource(
    val id: Int,
    val name: String,
    val url: String,
    val flag: Int = 0,
)

data class LiveStream(
    val url: String,
    val headers: Map<String, String> = emptyMap(),
)

data class LiveChannel(
    val name: String,
    val group: String,
    val logo: String? = null,
    val streams: List<LiveStream>,
) {
    val id: String get() = "$group|$name"
    val urls: List<String> get() = streams.map { it.url }
}

data class LiveGroup(
    val name: String,
    val channels: List<LiveChannel>,
)

class LiveStore(private val sources: List<LiveSource>) {
    constructor() : this(load())

    fun all(): List<LiveSource> = sources
    fun enabled(): List<LiveSource> =
        sources.filter { it.flag == 0 && it.url.trim().isNotEmpty() }

    companion object {
        private val json = Json { ignoreUnknownKeys = true; isLenient = true }

        private fun load(): List<LiveSource> {
            val text = LiveStore::class.java.classLoader
                ?.getResourceAsStream("lives.json")
                ?.bufferedReader(Charsets.UTF_8)
                ?.use { it.readText() }
                ?: throw IllegalStateException("未找到 lives.json")
            return json.decodeFromString(ListSerializer(LiveSource.serializer()), text)
        }
    }
}

object LiveResume {
    data class Pick(val group: LiveGroup, val channel: LiveChannel)

    fun resolve(groups: List<LiveGroup>, lastChannelId: String?): Pick? {
        if (lastChannelId != null) {
            for (group in groups) {
                val channel = group.channels.firstOrNull { it.id == lastChannelId }
                if (channel != null) return Pick(group, channel)
            }
        }
        val group = groups.firstOrNull() ?: return null
        val channel = group.channels.firstOrNull() ?: return null
        return Pick(group, channel)
    }
}

object HLSPlaylistProbe {
    enum class Decision { PLAYABLE, FLV, MPEGTS, RETRY, REJECT }

    const val MAX_PENDING_ATTEMPTS = 5

    fun evaluate(statusCode: Int, contentType: String?, body: ByteArray, pendingAttempt: Int): Decision {
        if (statusCode == 202) return if (pendingAttempt >= MAX_PENDING_ATTEMPTS - 1) Decision.REJECT else Decision.RETRY
        if (statusCode !in 200..299) return Decision.REJECT
        val type = contentType.orEmpty().lowercase()
        if (looksLikeFLV(body, type)) return Decision.FLV
        if (looksLikeMPEGTS(body, type)) return Decision.MPEGTS
        if (looksLikeMP4(body, type)) return Decision.PLAYABLE
        var text = body.toString(Charsets.UTF_8).trim().removePrefix("\uFEFF")
        val isHls = type.contains("mpegurl") || text.uppercase().startsWith("#EXTM3U")
        if (isHls) {
            if (looksLikeDisguisedMediaPlaylist(text)) return Decision.MPEGTS
            return Decision.PLAYABLE
        }
        return Decision.REJECT
    }

    fun looksLikeFLV(body: ByteArray, contentType: String): Boolean {
        if ("flv" in contentType) return true
        return body.size >= 3 && body[0] == 0x46.toByte() && body[1] == 0x4C.toByte() && body[2] == 0x56.toByte()
    }

    fun looksLikeMPEGTS(body: ByteArray, contentType: String): Boolean {
        if ("mp2t" in contentType || "mpegts" in contentType) return true
        val packetSize = 188
        if (body.size < packetSize) return false
        val searchLimit = minOf(body.size, packetSize)
        for (offset in 0 until searchLimit) {
            if (body[offset] == 0x47.toByte()) {
                val next = offset + packetSize
                return if (next < body.size) body[next] == 0x47.toByte() else offset == 0
            }
        }
        return false
    }

    fun looksLikeMP4(body: ByteArray, contentType: String): Boolean {
        if ("mp4" in contentType || "iso.segment" in contentType) return true
        return body.size >= 8 &&
            body[4] == 0x66.toByte() &&
            body[5] == 0x74.toByte() &&
            body[6] == 0x79.toByte() &&
            body[7] == 0x70.toByte()
    }

    fun looksLikeDisguisedMediaPlaylist(text: String): Boolean {
        val lower = text.lowercase()
        return listOf(".jpeg", ".jpg", ".png", ".gif", ".webp").any { it in lower }
    }
}

object VodMediaProbe {
    fun isLikelyPlayable(url: String, headers: Map<String, String>): Boolean {
        return try {
            val response = com.heibaimiao.multilivetv.net.HttpClient.get(url, extraHeaders = headers, range = "bytes=0-2047")
            when (HLSPlaylistProbe.evaluate(response.code, response.contentType, response.body, 0)) {
                HLSPlaylistProbe.Decision.PLAYABLE,
                HLSPlaylistProbe.Decision.FLV,
                HLSPlaylistProbe.Decision.MPEGTS,
                -> true
                else -> false
            }
        } catch (_: Exception) {
            false
        }
    }
}
