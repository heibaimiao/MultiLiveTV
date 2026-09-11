package com.heibaimiao.multilivetv.parser

import com.heibaimiao.multilivetv.model.Episode
import com.heibaimiao.multilivetv.model.PlaySource

data class PlaybackCandidate(
    val sourceId: Int,
    val episode: Episode,
)

object VodPlaybackFailover {
    fun candidates(
        playSources: List<PlaySource>,
        selectedIndex: Int,
        episode: Episode,
        fallbackSourceId: Int,
        maxCandidates: Int = 4,
    ): List<PlaybackCandidate> {
        if (playSources.isEmpty()) {
            return listOf(PlaybackCandidate(fallbackSourceId, episode))
        }
        val selected = playSources[selectedIndex.coerceIn(0, playSources.lastIndex)]
        val episodeIndex = selected.episodes.indexOfFirst { it.url == episode.url && it.name == episode.name }
            .takeIf { it >= 0 }
            ?: selected.episodes.indexOfFirst { it.url == episode.url }.takeIf { it >= 0 }
            ?: selected.episodes.indexOfFirst { it.name == episode.name }.takeIf { it >= 0 }
            ?: 0

        val result = mutableListOf<PlaybackCandidate>()
        val seen = mutableSetOf<String>()

        fun append(source: PlaySource, ep: Episode) {
            val sourceId = source.sourceId ?: fallbackSourceId
            val key = "$sourceId|${ep.url}"
            if (!seen.add(key)) return
            result += PlaybackCandidate(sourceId, ep)
        }

        append(selected, episode)
        for (source in PlayLineWeighting.sort(playSources)) {
            if (source.key == selected.key) continue
            val ep = episodeMatching(source, episodeIndex, episode.name) ?: continue
            if (!PlaybackSupport.isDirectMediaURL(ep.url)) continue
            append(source, ep)
            if (result.size >= maxCandidates) break
        }
        return result
    }

    fun nextIndex(after: Int, count: Int): Int? {
        val next = after + 1
        return if (next < count) next else null
    }

    private fun episodeMatching(source: PlaySource, episodeIndex: Int, preferredName: String): Episode? {
        source.episodes.getOrNull(episodeIndex)?.let {
            if (PlaybackSupport.isDirectMediaURL(it.url)) return it
        }
        source.episodes.firstOrNull { it.name == preferredName && PlaybackSupport.isDirectMediaURL(it.url) }?.let {
            return it
        }
        return source.episodes.firstOrNull { PlaybackSupport.isDirectMediaURL(it.url) }
    }
}
