package com.heibaimiao.multilivetv.live

import com.heibaimiao.multilivetv.net.RemoteMediaURL

object M3UPlaylistParser {
    const val UNGROUPED = "未分组"

    fun parse(text: String): List<LiveGroup> = parseM3U(normalizedLines(text))

    fun parsePlaylist(text: String): List<LiveGroup> {
        val lines = normalizedLines(text)
        return if (looksLikeM3U(lines)) parseM3U(lines) else parseTxt(lines)
    }

    fun merge(playlists: List<List<LiveGroup>>): List<LiveGroup> {
        val groupOrder = mutableListOf<String>()
        val channelsByGroup = mutableMapOf<String, MutableList<LiveChannel>>()
        for (playlist in playlists) {
            for (group in playlist) {
                if (group.name !in groupOrder) groupOrder += group.name
                val list = channelsByGroup.getOrPut(group.name) { mutableListOf() }
                for (channel in group.channels) {
                    val index = list.indexOfFirst { it.name == channel.name }
                    if (index >= 0) {
                        val existing = list[index]
                        val streams = existing.streams.toMutableList()
                        for (stream in channel.streams) {
                            if (streams.none { it.url == stream.url }) streams += stream
                        }
                        list[index] = existing.copy(streams = streams, logo = existing.logo ?: channel.logo)
                    } else {
                        list += channel
                    }
                }
            }
        }
        return groupOrder.map { LiveGroup(it, channelsByGroup[it].orEmpty()) }
    }

    fun playableMediaURL(line: String): String? {
        val url = mediaURL(line)
        return if (RemoteMediaURL.parse(url) != null) url else null
    }

    fun mediaURL(line: String): String {
        val trimmed = line.trim()
        val withoutPipe = if ('|' in trimmed) trimmed.substringBefore('|').trim() else trimmed
        return LivePlayback.stripSourceTag(withoutPipe)
    }

    private fun normalizedLines(text: String): List<String> =
        text.removePrefix("\uFEFF").replace("\r\n", "\n").replace("\r", "\n").split('\n').map { it.trim() }

    private fun looksLikeM3U(lines: List<String>): Boolean =
        lines.any { it.uppercase().startsWith("#EXTM3U") || it.uppercase().startsWith("#EXTINF:") }

    private fun parseM3U(lines: List<String>): List<LiveGroup> {
        val groupOrder = mutableListOf<String>()
        val channelsByGroup = mutableMapOf<String, MutableList<LiveChannel>>()
        var pending: Pending? = null
        for (line in lines) {
            if (line.isEmpty()) continue
            if (line.uppercase().startsWith("#EXTINF:")) {
                val ext = parseExtInf(line)
                pending = Pending(ext.first, ext.second, ext.third, mutableMapOf())
                continue
            }
            if (line.uppercase().startsWith("#EXTVLCOPT:")) {
                val parsed = LivePlayback.headerFromEXTVLCOPT(line)
                if (pending != null && parsed != null) pending.headers[parsed.first] = parsed.second
                continue
            }
            if (line.startsWith("#")) continue
            val current = pending ?: continue
            val parts = LivePlayback.splitKodiLine(line)
            val url = playableMediaURL(parts.first) ?: continue
            val headers = current.headers.toMutableMap()
            headers.putAll(LivePlayback.headersFromKodiSuffix(parts.second))
            appendStream(LiveStream(url, headers), current.name, current.group.ifEmpty { UNGROUPED }, current.logo, groupOrder, channelsByGroup)
            pending = null
        }
        return groupOrder.map { LiveGroup(it, channelsByGroup[it].orEmpty()) }
    }

    private fun parseTxt(lines: List<String>): List<LiveGroup> {
        val groupOrder = mutableListOf<String>()
        val channelsByGroup = mutableMapOf<String, MutableList<LiveChannel>>()
        var currentGroup = UNGROUPED
        for (line in expandedTxtLines(lines)) {
            if (line.isEmpty()) continue
            val genre = txtGenreName(line)
            if (genre != null) {
                currentGroup = genre.ifEmpty { UNGROUPED }
                continue
            }
            val comma = line.indexOf(',')
            if (comma < 0) continue
            val name = line.substring(0, comma).trim()
            val rest = line.substring(comma + 1).trim()
            if (name.isEmpty()) continue
            for (raw in txtURLs(rest)) {
                val parts = LivePlayback.splitKodiLine(raw)
                val url = playableMediaURL(parts.first) ?: continue
                appendStream(LiveStream(url, LivePlayback.headersFromKodiSuffix(parts.second)), name, currentGroup, null, groupOrder, channelsByGroup)
            }
        }
        return groupOrder.map { LiveGroup(it, channelsByGroup[it].orEmpty()) }
    }

    fun expandedTxtLines(lines: List<String>): List<String> =
        lines.flatMap { line ->
            var current = line
            while (current.startsWith(",")) current = current.drop(1).trimStart()
            splitGluedChannelLines(current)
        }

    fun splitGluedChannelLines(line: String): List<String> {
        val pattern = Regex("""([A-Za-z0-9./?=&%~_+-])(\p{Han}+,https?://)""")
        return pattern.replace(line, "$1\n$2").split('\n').map { it.trim() }.filter { it.isNotEmpty() }
    }

    private fun txtGenreName(line: String): String? {
        val marker = Regex("""#genre#""", RegexOption.IGNORE_CASE)
        val match = marker.find(line) ?: return null
        return line.substring(0, match.range.first).trim(',', ' ', '\t')
    }

    private fun txtURLs(rest: String): List<String> {
        val pieces = mutableListOf<String>()
        for (chunk in rest.split('#').map { it.trim() }.filter { it.isNotEmpty() }) {
            if (',' in chunk) {
                chunk.split(',').map { it.trim() }.filter { "://" in it }.forEach { pieces += it }
            } else if ("://" in chunk) {
                pieces += chunk
            }
        }
        return pieces
    }

    private fun appendStream(
        stream: LiveStream,
        name: String,
        group: String,
        logo: String?,
        groupOrder: MutableList<String>,
        channelsByGroup: MutableMap<String, MutableList<LiveChannel>>,
    ) {
        if (group !in groupOrder) groupOrder += group
        val list = channelsByGroup.getOrPut(group) { mutableListOf() }
        val index = list.indexOfFirst { it.name == name }
        if (index >= 0) {
            val existing = list[index]
            val streams = existing.streams.toMutableList()
            if (streams.none { it.url == stream.url }) streams += stream
            list[index] = existing.copy(streams = streams, logo = existing.logo ?: logo)
        } else {
            list += LiveChannel(name, group, logo, listOf(stream))
        }
    }

    private fun parseExtInf(line: String): Triple<String, String, String?> {
        val rest = line.removePrefix("#EXTINF:")
        val comma = rest.lastIndexOf(',')
        if (comma < 0) return Triple(rest, UNGROUPED, null)
        val meta = rest.substring(0, comma)
        val name = rest.substring(comma + 1).trim()
        return Triple(name.ifEmpty { rest }, attribute(meta, "group-title") ?: UNGROUPED, attribute(meta, "tvg-logo"))
    }

    private fun attribute(text: String, key: String): String? {
        val start = Regex("""$key=""", RegexOption.IGNORE_CASE).find(text) ?: return null
        var rest = text.substring(start.range.last + 1).trimStart()
        if (rest.isEmpty()) return null
        val first = rest.first()
        if (first == '"' || first == '\'') {
            rest = rest.drop(1)
            val end = rest.indexOf(first)
            if (end < 0) return null
            return rest.substring(0, end).trim().ifEmpty { null }
        }
        return rest.takeWhile { !it.isWhitespace() }.trim().ifEmpty { null }
    }

    private data class Pending(
        val name: String,
        val group: String,
        val logo: String?,
        val headers: MutableMap<String, String>,
    )
}

object LivePlayback {
    fun stripSourceTag(url: String): String {
        val trimmed = url.trim()
        val dollar = trimmed.indexOf('$')
        if (dollar < 0) return trimmed
        val suffix = trimmed.substring(dollar + 1)
        if ('=' in suffix || '&' in suffix || '/' in suffix || "://" in suffix) return trimmed
        return trimmed.substring(0, dollar)
    }

    fun prefersVLC(url: String): Boolean {
        val lower = stripSourceTag(url).lowercase()
        return "/udp/" in lower || "/rtp/" in lower
    }

    fun splitKodiLine(line: String): Pair<String, String> {
        val trimmed = line.trim()
        val pipe = trimmed.indexOf('|')
        if (pipe < 0) return trimmed to ""
        return trimmed.substring(0, pipe).trim() to trimmed.substring(pipe + 1)
    }

    fun headersFromKodiSuffix(suffix: String): Map<String, String> {
        if (suffix.isEmpty()) return emptyMap()
        val headers = mutableMapOf<String, String>()
        for (pair in suffix.split('&')) {
            val eq = pair.indexOf('=')
            if (eq < 0) continue
            val name = canonicalHeaderName(pair.substring(0, eq)) ?: continue
            val rawValue = pair.substring(eq + 1)
            headers[name] = java.net.URLDecoder.decode(rawValue, Charsets.UTF_8)
        }
        return headers
    }

    fun headerFromEXTVLCOPT(line: String): Pair<String, String>? {
        if (!line.uppercase().startsWith("#EXTVLCOPT:")) return null
        val rest = line.substring("#EXTVLCOPT:".length)
        val eq = rest.indexOf('=')
        if (eq < 0) return null
        val name = canonicalHeaderName(rest.substring(0, eq)) ?: return null
        val rawValue = rest.substring(eq + 1).trim()
        if (rawValue.isEmpty()) return null
        return name to java.net.URLDecoder.decode(rawValue, Charsets.UTF_8)
    }

    fun canonicalHeaderName(key: String): String? = when (key.trim().lowercase()) {
        "user-agent", "http-user-agent" -> "User-Agent"
        "referer", "referrer", "http-referer", "http-referrer" -> "Referer"
        "origin", "http-origin" -> "Origin"
        "cookie", "http-cookie" -> "Cookie"
        else -> null
    }
}
