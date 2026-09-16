package com.heibaimiao.multilivetv.live

import android.content.Context

class PrefsLiveChannelMemory(context: Context) : LiveChannelMemory {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    override var lastGroupName: String?
        get() = prefs.getString(KEY_GROUP, null)
        set(value) {
            prefs.edit().putString(KEY_GROUP, value).apply()
        }

    override var lastChannelId: String?
        get() = prefs.getString(KEY_CHANNEL, null)
        set(value) {
            prefs.edit().putString(KEY_CHANNEL, value).apply()
        }

    companion object {
        private const val PREFS = "live_channel_memory"
        private const val KEY_GROUP = "lastGroup"
        private const val KEY_CHANNEL = "lastChannelId"
    }
}
