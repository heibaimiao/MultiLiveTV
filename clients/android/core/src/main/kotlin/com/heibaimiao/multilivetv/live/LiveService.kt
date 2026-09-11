package com.heibaimiao.multilivetv.live

import com.heibaimiao.multilivetv.net.HttpClient
import com.heibaimiao.multilivetv.net.RemoteMediaURL
import com.heibaimiao.multilivetv.net.RequestFailure
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class LiveService(private val store: LiveStore = runCatching { LiveStore() }.getOrElse { LiveStore(emptyList()) }) {
    suspend fun reload(): Pair<List<LiveGroup>, String?> = withContext(Dispatchers.IO) {
        val sources = store.enabled()
        if (sources.isEmpty()) return@withContext emptyList<LiveGroup>() to "请在 lives.json 填写 M3U 地址"
        val playlists = mutableListOf<List<LiveGroup>>()
        var lastError: String? = null
        for (source in sources) {
            try {
                playlists += fetchPlaylist(source.url)
            } catch (error: Exception) {
                lastError = RequestFailure.userFacingMessage(error)
            }
        }
        val merged = M3UPlaylistParser.merge(playlists)
        if (merged.isEmpty()) merged to (lastError ?: "直播列表为空") else merged to null
    }

    private fun fetchPlaylist(urlString: String): List<LiveGroup> {
        val url = RemoteMediaURL.parse(urlString) ?: urlString
        val text = HttpClient.getOrThrow(url).text()
        return M3UPlaylistParser.parsePlaylist(text)
    }
}
