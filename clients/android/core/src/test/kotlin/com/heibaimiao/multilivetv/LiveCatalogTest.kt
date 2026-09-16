package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.live.LiveCatalog
import com.heibaimiao.multilivetv.live.LiveChannel
import com.heibaimiao.multilivetv.live.LiveGroup
import com.heibaimiao.multilivetv.live.LiveStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LiveCatalogTest {
    @Test
    fun dropsChannelWithoutPlayableStream() {
        val sports = LiveGroup(
            "体育",
            listOf(
                channel("纬来体育", "https://a.example/a.m3u8"),
                channel("无效", ""),
                channel("无地址", streams = emptyList()),
                channel(" ", "https://a.example/blank.m3u8"),
            ),
        )
        val visible = LiveCatalog.visibleGroups(listOf(sports))
        assertEquals(listOf("纬来体育"), visible.single().channels.map { it.name })
    }

    @Test
    fun dropsGroupWhenEveryChannelIsInvalid() {
        val empty = LiveGroup("空分组", emptyList())
        val broken = LiveGroup("测试源", listOf(channel("坏", "not-a-url")))
        val sports = LiveGroup("体育", listOf(channel("纬来体育", "https://a.example/a.m3u8")))
        val visible = LiveCatalog.visibleGroups(listOf(empty, broken, sports))
        assertEquals(listOf("体育"), visible.map { it.name })
    }

    @Test
    fun keepsValidGroupsWhenOthersFail() {
        val sports = LiveGroup("体育", listOf(channel("A", "https://a.example/a.m3u8")))
        val satellite = LiveGroup("卫视", listOf(channel("B", "https://b.example/b.m3u8"), channel("坏", "")))
        val visible = LiveCatalog.visibleGroups(listOf(sports, satellite))
        assertEquals(listOf("体育", "卫视"), visible.map { it.name })
        assertEquals(listOf("B"), visible[1].channels.map { it.name })
    }

    @Test
    fun resolveSelectionKeepsCurrentWhenStillValid() {
        val groups = listOf(
            LiveGroup("体育", listOf(channel("A", "https://a.example/a.m3u8"))),
            LiveGroup("卫视", listOf(channel("B", "https://b.example/b.m3u8"))),
        )
        assertEquals("卫视", LiveCatalog.resolveSelection(groups, "卫视")?.name)
    }

    @Test
    fun resolveSelectionFallsBackWhenCurrentGroupDisappears() {
        val groups = listOf(
            LiveGroup("卫视", listOf(channel("B", "https://b.example/b.m3u8"))),
        )
        assertEquals("卫视", LiveCatalog.resolveSelection(groups, "体育")?.name)
    }

    @Test
    fun resolveSelectionIsNullWhenNothingPlayable() {
        assertNull(LiveCatalog.resolveSelection(emptyList(), "体育"))
        assertTrue(LiveCatalog.visibleGroups(listOf(LiveGroup("空", emptyList()))).isEmpty())
    }

    private fun channel(
        name: String,
        url: String = "https://a.example/${name}.m3u8",
        streams: List<LiveStream> = if (url.isEmpty()) listOf(LiveStream("")) else listOf(LiveStream(url)),
    ) = LiveChannel(name = name, group = "组", streams = streams)
}
