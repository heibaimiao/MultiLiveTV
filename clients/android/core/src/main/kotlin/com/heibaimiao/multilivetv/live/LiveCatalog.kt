package com.heibaimiao.multilivetv.live

import com.heibaimiao.multilivetv.net.RemoteMediaURL

object LiveCatalog {
    fun isPlayable(channel: LiveChannel): Boolean {
        if (channel.name.isBlank()) return false
        return channel.streams.any { RemoteMediaURL.parse(it.url) != null }
    }

    fun visibleGroups(groups: List<LiveGroup>): List<LiveGroup> =
        groups.map { group ->
            group.copy(channels = group.channels.filter(::isPlayable))
        }.filter { it.name.isNotBlank() && it.channels.isNotEmpty() }

    fun resolveSelection(groups: List<LiveGroup>, selectedName: String?): LiveGroup? {
        if (groups.isEmpty()) return null
        return groups.firstOrNull { it.name == selectedName } ?: groups.first()
    }
}
