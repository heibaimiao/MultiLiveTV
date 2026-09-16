package com.heibaimiao.multilivetv.live

/**
 * Last watched live channel memory. Implementations may use SharedPreferences / files.
 */
interface LiveChannelMemory {
    var lastGroupName: String?
    var lastChannelId: String?

    fun remember(groupName: String, channelId: String) {
        lastGroupName = groupName
        lastChannelId = channelId
    }
}

class InMemoryLiveChannelMemory : LiveChannelMemory {
    override var lastGroupName: String? = null
    override var lastChannelId: String? = null
}
