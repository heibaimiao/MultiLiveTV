package com.heibaimiao.multilivetv.live

object LiveChannelNav {
    fun step(group: LiveGroup, channel: LiveChannel, delta: Int): LiveChannel? {
        val channels = group.channels
        if (channels.isEmpty() || delta == 0) return null
        val current = channels.indexOfFirst { it.id == channel.id }.takeIf { it >= 0 } ?: return null
        val next = (current + delta).mod(channels.size)
        val candidate = channels[next]
        return if (candidate.id == channel.id) null else candidate
    }
}
