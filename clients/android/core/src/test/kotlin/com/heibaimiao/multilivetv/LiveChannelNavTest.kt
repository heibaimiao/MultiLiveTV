package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.live.LiveChannel
import com.heibaimiao.multilivetv.live.LiveChannelNav
import com.heibaimiao.multilivetv.live.LiveGroup
import com.heibaimiao.multilivetv.live.LiveStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class LiveChannelNavTest {
    private fun channel(name: String) = LiveChannel(
        name = name,
        group = "卫视",
        streams = listOf(LiveStream("https://a.example/$name.m3u8")),
    )

    @Test
    fun stepsWithinGroupAndWraps() {
        val hunan = channel("湖南卫视")
        val zhejiang = channel("浙江卫视")
        val beijing = channel("北京卫视")
        val group = LiveGroup("卫视", listOf(hunan, zhejiang, beijing))

        assertEquals(zhejiang.id, LiveChannelNav.step(group, hunan, 1)?.id)
        assertEquals(beijing.id, LiveChannelNav.step(group, hunan, -1)?.id)
        assertEquals(hunan.id, LiveChannelNav.step(group, beijing, 1)?.id)
    }

    @Test
    fun singleChannelDoesNotZap() {
        val only = channel("湖南卫视")
        val group = LiveGroup("卫视", listOf(only))
        assertNull(LiveChannelNav.step(group, only, 1))
        assertNull(LiveChannelNav.step(group, only, -1))
    }
}
