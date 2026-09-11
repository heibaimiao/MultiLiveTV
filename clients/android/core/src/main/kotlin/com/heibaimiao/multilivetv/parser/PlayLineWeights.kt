package com.heibaimiao.multilivetv.parser

import com.heibaimiao.multilivetv.source.SourceHealthStore
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class PlayLineWeights(
    val version: Int,
    val defaultWeight: Int,
    val byPlayFrom: Map<String, Int> = emptyMap(),
    val byProviderId: Map<String, Int> = emptyMap(),
    val bySourceId: Map<String, Int>? = emptyMap(),
) {
    fun weight(playFrom: String?, providerId: String?, sourceId: Int? = null): Int {
        providerId?.let { byProviderId[it] }?.let { return it }
        playFrom?.let { byPlayFrom[it] }?.let { return it }
        if (sourceId != null && sourceId != 0) {
            bySourceId?.get(sourceId.toString())?.let { return it }
        }
        return defaultWeight
    }

    companion object {
        private val json = Json { ignoreUnknownKeys = true; isLenient = true }

        val bundled: PlayLineWeights by lazy {
            val text = PlayLineWeights::class.java.classLoader
                ?.getResourceAsStream("play-line-weights.json")
                ?.bufferedReader(Charsets.UTF_8)
                ?.use { it.readText() }
            if (text != null) json.decodeFromString(serializer(), text) else fallback
        }

        private val fallback = PlayLineWeights(
            version = 2,
            defaultWeight = 100,
            byPlayFrom = mapOf(
                "qq" to 2000, "腾讯" to 2000, "腾讯视频" to 2000,
                "qiyi" to 1990, "爱奇艺" to 1990,
                "youku" to 1980, "优酷" to 1980,
                "mgtv" to 1970, "芒果" to 1970, "芒果TV" to 1970,
                "huo" to 1900, "lv2" to 1890, "rrys" to 1880,
                "bytedance" to 1870, "dong" to 1860,
                "cloudflare" to 1850, "cloudflare-4k" to 1840, "hnm3u8" to 920,
            ),
            byProviderId = mapOf(
                "official-qq" to 2000, "official-qiyi" to 1990, "official-youku" to 1980,
                "official-mgtv" to 1970, "official-v" to 1900, "bytevod-lv2" to 1890,
                "official-r" to 1880, "bytedance" to 1870, "dong" to 1860,
                "bytevod-cloudflare" to 1850, "bytevod-cloudflare-4k" to 1840,
                "official-hot-playback" to 1830,
            ),
            bySourceId = emptyMap(),
        )
    }
}

object PlayLineWeighting {
    var table: PlayLineWeights = PlayLineWeights.bundled
    var ticketEnabled: Boolean = true
    var healthStore: SourceHealthStore = SourceHealthStore.shared
    var playPriorityBySourceId: Map<Int, Int> = emptyMap()

    fun weight(playFrom: String?, providerId: String? = null, sourceId: Int? = null): Int =
        table.weight(playFrom, providerId, sourceId)

    fun sourceWeight(sourceId: Int): Int =
        playPriorityBySourceId[sourceId] ?: weight(playFrom = null, providerId = null, sourceId = sourceId)

    fun effectivePlayScore(
        playFrom: String?,
        providerId: String?,
        sourceId: Int?,
        baseWeight: Int = 0,
    ): Int {
        val tableW = when {
            providerId != null && table.byProviderId[providerId] != null -> table.byProviderId.getValue(providerId)
            playFrom != null && table.byPlayFrom[playFrom] != null -> table.byPlayFrom.getValue(playFrom)
            sourceId != null && sourceId != 0 -> playPriorityBySourceId[sourceId]
                ?: table.bySourceId?.get(sourceId.toString())
                ?: table.defaultWeight
            else -> table.defaultWeight
        }
        val resolved = if (baseWeight > 0) baseWeight else tableW
        val health = sourceId?.let { healthStore.healthScore(it) } ?: 0
        return resolved + health
    }

    fun forDetailDisplay(sources: List<com.heibaimiao.multilivetv.model.PlaySource>) =
        sort(sources.map { annotate(it) })

    fun annotate(
        source: com.heibaimiao.multilivetv.model.PlaySource,
        rawPlayFrom: String? = null,
    ): com.heibaimiao.multilivetv.model.PlaySource {
        val playFrom = (rawPlayFrom ?: source.playFrom ?: source.key).trim()
        val resolvedWeight = effectivePlayScore(
            playFrom = playFrom,
            providerId = source.providerId,
            sourceId = source.sourceId,
            baseWeight = source.weight,
        )
        return source.copy(
            weight = resolvedWeight,
            mode = source.mode.ifEmpty { "direct" },
            playFrom = playFrom,
        )
    }

    fun sort(sources: List<com.heibaimiao.multilivetv.model.PlaySource>): List<com.heibaimiao.multilivetv.model.PlaySource> =
        sources.sortedWith(
            compareByDescending<com.heibaimiao.multilivetv.model.PlaySource> { it.weight }
                .thenByDescending { playabilityScore(it) }
                .thenByDescending { it.episodes.size },
        )

    fun preferredPlayableIndex(
        sources: List<com.heibaimiao.multilivetv.model.PlaySource>,
        episodeIndex: Int = 0,
        ticketEnabled: Boolean = this.ticketEnabled,
    ): Int {
        if (sources.isEmpty()) return 0
        for (candidate in sort(sources)) {
            if (!episodePlayable(candidate, episodeIndex, ticketEnabled)) continue
            val index = sources.indexOfFirst { it.key == candidate.key }
            if (index >= 0) return index
        }
        return 0
    }

    fun episodePlayable(
        source: com.heibaimiao.multilivetv.model.PlaySource,
        episodeIndex: Int,
        ticketEnabled: Boolean,
    ): Boolean {
        val ep = source.episodes.getOrNull(episodeIndex) ?: source.episodes.firstOrNull()
        val url = (ep?.url ?: source.ticket.orEmpty()).trim()
        if (url.isEmpty()) return false
        if (source.mode == "ticket") return ticketEnabled
        return PlaybackSupport.isDirectMediaURL(url)
    }

    private fun playabilityScore(source: com.heibaimiao.multilivetv.model.PlaySource): Int =
        source.episodes.count { PlaybackSupport.isDirectMediaURL(it.url) }
}
