package com.heibaimiao.multilivetv.parser

import com.heibaimiao.multilivetv.model.Source
import com.heibaimiao.multilivetv.net.NetworkConfig
import java.net.URI

object PlaybackSupport {
    fun isDirectMediaURL(url: String): Boolean {
        val trimmed = url.trim()
        val parsed = runCatching { URI(trimmed) }.getOrNull() ?: return false
        val scheme = parsed.scheme?.lowercase() ?: return false
        if (scheme != "http" && scheme != "https") return false
        val path = parsed.path.lowercase()
        return path.endsWith(".m3u8") ||
            path.endsWith(".mp4") ||
            path.endsWith(".mkv") ||
            path.endsWith(".flv") ||
            path.endsWith(".mov") ||
            path.endsWith(".m3u")
    }

    fun httpHeaders(source: Source, playbackURL: String): Map<String, String> {
        val headers = mutableMapOf("User-Agent" to NetworkConfig.USER_AGENT)
        val uri = runCatching { URI(playbackURL) }.getOrNull()
        val host = uri?.host
        if (!host.isNullOrEmpty()) {
            val origin = "${uri.scheme ?: "https"}://$host/"
            headers["Referer"] = origin
            headers["Origin"] = origin
        } else {
            val sourceUri = runCatching { URI(source.url) }.getOrNull()
            val sourceHost = sourceUri?.host
            if (!sourceHost.isNullOrEmpty()) {
                val origin = "${sourceUri.scheme ?: "https"}://$sourceHost/"
                headers["Referer"] = origin
                headers["Origin"] = origin
            }
        }
        return headers
    }

    fun userFacingError(url: String, underlying: String?): String {
        val lower = underlying.orEmpty().lowercase()
        if ("timeout" in lower) return "播放超时，请换线路重试"
        if (isDirectMediaURL(url) || url.startsWith("http")) {
            if (!underlying.isNullOrBlank() && !looksLikeSystemPlaybackFailure(underlying)) {
                return underlying
            }
            return "播放失败，请换线路重试"
        }
        return "当前线路为网页链接，App 无法直接播放。请换带 m3u8 的线路（如猫眼、无忧、影剧）。"
    }

    fun looksLikeSystemPlaybackFailure(message: String): Boolean {
        val lower = message.lowercase()
        return "cannot decode" in lower ||
            "exoplayer" in lower ||
            "source error" in lower ||
            "http 602" in lower ||
            "unrecognized input" in lower
    }
}
