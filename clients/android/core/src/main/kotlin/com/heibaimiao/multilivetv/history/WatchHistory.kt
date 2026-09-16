package com.heibaimiao.multilivetv.history

import com.heibaimiao.multilivetv.model.DetailResponse
import com.heibaimiao.multilivetv.model.Episode
import com.heibaimiao.multilivetv.model.PlaySource
import com.heibaimiao.multilivetv.model.VodItem
import com.heibaimiao.multilivetv.parser.PlaybackCandidate
import com.heibaimiao.multilivetv.parser.VodPlaybackFailover
import com.heibaimiao.multilivetv.vod.VodService
import kotlinx.serialization.Serializable

data class VodPlaybackRequest(
    val item: VodItem,
    val candidates: List<PlaybackCandidate>,
    val resumePositionMs: Long = 0L,
    val sourceName: String = "",
    val episodeIndex: Int = 0,
)

@Serializable
data class WatchHistoryRecord(
    val videoId: String,
    val vodId: String = "",
    val episodeId: String = "",
    val title: String = "",
    val episodeTitle: String = "",
    val episodeIndex: Int = 0,
    val cover: String = "",
    val sourceId: Int = 0,
    val sourceName: String = "",
    val positionMs: Long = 0L,
    val durationMs: Long = 0L,
    val progress: Double = 0.0,
    val lastPlayTime: Long = 0L,
    val completed: Boolean = false,
)

object WatchHistoryProgress {
    const val NEAR_END_MS = 10_000L

    fun sanitizePosition(positionMs: Long, durationMs: Long): Long {
        if (durationMs <= 0L) return 0L
        return positionMs.coerceIn(0L, durationMs)
    }

    fun isCompleted(positionMs: Long, durationMs: Long): Boolean {
        if (durationMs <= 0L) return false
        val position = sanitizePosition(positionMs, durationMs)
        val threshold = if (durationMs <= NEAR_END_MS) durationMs else durationMs - NEAR_END_MS
        return position >= threshold
    }

    fun progressOf(positionMs: Long, durationMs: Long, completed: Boolean): Double {
        if (completed) return 1.0
        if (durationMs <= 0L) return 0.0
        return (sanitizePosition(positionMs, durationMs).toDouble() / durationMs.toDouble()).coerceIn(0.0, 1.0)
    }

    fun normalize(record: WatchHistoryRecord, now: Long = record.lastPlayTime): WatchHistoryRecord {
        val duration = record.durationMs.coerceAtLeast(0L)
        val position = sanitizePosition(record.positionMs, duration)
        val completed = record.completed || isCompleted(position, duration)
        return record.copy(
            videoId = record.videoId.trim(),
            vodId = record.vodId.trim(),
            episodeId = record.episodeId,
            title = record.title.trim(),
            episodeTitle = record.episodeTitle.trim(),
            episodeIndex = record.episodeIndex.coerceAtLeast(0),
            cover = record.cover,
            sourceId = record.sourceId,
            sourceName = record.sourceName.trim(),
            positionMs = if (completed && duration > 0L) duration else position,
            durationMs = duration,
            progress = progressOf(position, duration, completed),
            lastPlayTime = now,
            completed = completed,
        )
    }

    fun formatClock(ms: Long): String {
        val totalSec = (ms / 1000L).coerceAtLeast(0L)
        val hours = totalSec / 3600L
        val minutes = (totalSec % 3600L) / 60L
        val seconds = totalSec % 60L
        return if (hours > 0L) {
            "$hours:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}"
        } else {
            "$minutes:${seconds.toString().padStart(2, '0')}"
        }
    }

    fun progressLabel(record: WatchHistoryRecord): String {
        if (record.completed) return "已看完"
        return "已播放 ${formatClock(record.positionMs)} / ${formatClock(record.durationMs)}"
    }

    fun fromPlayback(
        item: VodItem,
        episode: Episode,
        episodeIndex: Int,
        sourceId: Int,
        sourceName: String,
        positionMs: Long,
        durationMs: Long,
        now: Long,
    ): WatchHistoryRecord = normalize(
        WatchHistoryRecord(
            videoId = item.id,
            vodId = item.vodId,
            episodeId = episode.url,
            title = item.vodName,
            episodeTitle = episode.name,
            episodeIndex = episodeIndex.coerceAtLeast(0),
            cover = item.vodPic,
            sourceId = sourceId,
            sourceName = sourceName,
            positionMs = positionMs,
            durationMs = durationMs,
            lastPlayTime = now,
        ),
        now = now,
    )
}

object WatchHistoryDisplay {
    private val qualityOnly = Regex(
        """^(?:U?HD|FHD|UHD|4K|8K|720P|1080P|2160P|蓝光|高清|超清|流畅|正片|预告|花絮|全集|完整版)$""",
        RegexOption.IGNORE_CASE,
    )

    const val showPlayingOverlay: Boolean = false

    fun heading(): String = "接着看"

    fun continueAction(clock: String): String = "从 $clock 继续"

    fun restartAction(): String = "从头播放"

    fun episodeLine(title: String, episodeTitle: String): String? {
        val episode = episodeTitle.trim()
        if (episode.isEmpty()) return null
        if (episode.equals(title.trim(), ignoreCase = true)) return null
        if (qualityOnly.matches(episode)) return null
        return episode
    }

    fun showProgressBar(durationMs: Long): Boolean = durationMs > 0L
}

object WatchHistoryResume {
    fun lookup(store: WatchHistoryStore, item: VodItem): WatchHistoryRecord? {
        store.getByVideoId(item.id)?.let { return it }
        val vodId = item.vodId.trim()
        if (vodId.isEmpty()) return null
        return store.getAll().firstOrNull { record ->
            record.vodId == vodId && (record.sourceId == 0 || record.sourceId == item.resolvedSourceId)
        }
    }

    fun resumePositionMs(record: WatchHistoryRecord): Long {
        if (record.completed) return 0L
        return WatchHistoryProgress.sanitizePosition(record.positionMs, record.durationMs)
    }

    fun playbackRequest(
        detail: DetailResponse,
        sourceIndex: Int,
        episode: Episode,
        resumePositionMs: Long = 0L,
    ): VodPlaybackRequest {
        val source = detail.playSources.getOrNull(sourceIndex)
        return VodPlaybackRequest(
            item = detail.vod,
            candidates = VodPlaybackFailover.candidates(
                playSources = detail.playSources,
                selectedIndex = sourceIndex,
                episode = episode,
                fallbackSourceId = detail.vod.resolvedSourceId,
            ),
            resumePositionMs = resumePositionMs.coerceAtLeast(0L),
            sourceName = source?.name.orEmpty(),
            episodeIndex = episodeIndex(source, episode),
        )
    }

    fun playbackRequest(detail: DetailResponse, record: WatchHistoryRecord, restart: Boolean = false): VodPlaybackRequest? {
        val match = findEpisode(detail, record) ?: return null
        return playbackRequest(
            detail = detail,
            sourceIndex = match.first,
            episode = match.second,
            resumePositionMs = if (restart) 0L else resumePositionMs(record),
        )
    }

    suspend fun loadRequest(vod: VodService, record: WatchHistoryRecord): VodPlaybackRequest {
        val sourceId = record.sourceId.takeIf { it > 0 }
            ?: record.videoId.substringBefore(':').toIntOrNull()
            ?: 0
        val vodId = record.vodId.ifBlank {
            record.videoId.substringAfter(':', missingDelimiterValue = "").ifBlank { record.videoId }
        }
        require(sourceId > 0 && vodId.isNotBlank()) { "历史记录不完整，无法继续播放" }
        val detail = vod.detail(sourceId, vodId)
        return playbackRequest(detail, record) ?: error("无法恢复上次播放的剧集")
    }

    fun findEpisode(detail: DetailResponse, record: WatchHistoryRecord): Pair<Int, Episode>? {
        val sources = detail.playSources
        if (sources.isEmpty()) return null
        val preferredSourceIndex = sources.indexOfFirst { source ->
            (source.sourceId ?: detail.vod.resolvedSourceId) == record.sourceId
        }.takeIf { it >= 0 } ?: 0
        val ordered = listOf(sources[preferredSourceIndex]) + sources.filterIndexed { index, _ -> index != preferredSourceIndex }
        for (source in ordered) {
            val episode = matchEpisode(source, record) ?: continue
            val sourceIndex = sources.indexOf(source).takeIf { it >= 0 } ?: preferredSourceIndex
            return sourceIndex to episode
        }
        return null
    }

    fun episodeIndex(source: PlaySource?, episode: Episode): Int {
        if (source == null) return 0
        val index = source.episodes.indexOfFirst { it.url == episode.url && it.name == episode.name }
            .takeIf { it >= 0 }
            ?: source.episodes.indexOfFirst { it.url == episode.url }.takeIf { it >= 0 }
            ?: source.episodes.indexOfFirst { it.name == episode.name }
        return index.coerceAtLeast(0)
    }

    private fun matchEpisode(source: PlaySource, record: WatchHistoryRecord): Episode? {
        source.episodes.firstOrNull { it.url == record.episodeId && record.episodeId.isNotBlank() }?.let { return it }
        source.episodes.firstOrNull { it.name == record.episodeTitle && record.episodeTitle.isNotBlank() }?.let { return it }
        source.episodes.getOrNull(record.episodeIndex)?.let { return it }
        return source.episodes.firstOrNull()
    }
}

class WatchHistoryRecorder(
    private val store: WatchHistoryStore,
    private val intervalMs: Long = 8_000L,
) {
    private var lastVideoId: String? = null
    private var lastWriteAt: Long = Long.MIN_VALUE / 2

    fun save(record: WatchHistoryRecord, force: Boolean) {
        val normalized = WatchHistoryProgress.normalize(record)
        if (normalized.videoId.isBlank()) return
        val now = normalized.lastPlayTime
        val sameItem = lastVideoId == normalized.videoId
        if (!force && sameItem && now - lastWriteAt < intervalMs) return
        lastVideoId = normalized.videoId
        lastWriteAt = now
        store.save(normalized)
    }
}
