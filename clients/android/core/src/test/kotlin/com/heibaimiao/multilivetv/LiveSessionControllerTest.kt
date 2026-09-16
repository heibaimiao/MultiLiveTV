package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.live.LiveChannel
import com.heibaimiao.multilivetv.live.LiveGroup
import com.heibaimiao.multilivetv.live.LivePreviewPolicy
import com.heibaimiao.multilivetv.live.LiveSelectionSync
import com.heibaimiao.multilivetv.live.LiveSessionController
import com.heibaimiao.multilivetv.live.LiveStream
import com.heibaimiao.multilivetv.live.LiveStreamFailover
import com.heibaimiao.multilivetv.live.LiveUiMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LiveSessionControllerTest {
    private fun channel(name: String, group: String = "卫视", urls: List<String> = listOf("https://a.example/1.m3u8")) =
        LiveChannel(
            name = name,
            group = group,
            streams = urls.map { LiveStream(it) },
        )

    @Test
    fun previewDebounceIs600ms() {
        assertEquals(600L, LivePreviewPolicy.DEBOUNCE_MS)
    }

    @Test
    fun focusChangeBumpsGenerationAndCancelsStalePreview() {
        val ctrl = LiveSessionController()
        ctrl.markBrowseReady()
        val mode = ctrl.state.modeGeneration
        val a = channel("A")
        val b = channel("B")
        val c = channel("C")

        val genA = ctrl.onChannelFocused(a)
        val genB = ctrl.onChannelFocused(b)
        val genC = ctrl.onChannelFocused(c)

        assertTrue(genC > genB && genB > genA)
        assertFalse(ctrl.shouldApplyPreview(genA, a.id, mode))
        assertFalse(ctrl.shouldApplyPreview(genB, b.id, mode))
        assertTrue(ctrl.shouldApplyPreview(genC, c.id, mode))
        assertEquals(c.id, ctrl.state.focusedChannelId)
    }

    @Test
    fun enterWatchBumpsModeGenerationAndInvalidatesPendingPreview() {
        val ctrl = LiveSessionController()
        val ch = channel("东南卫视")
        val modeBefore = ctrl.state.modeGeneration
        val gen = ctrl.onChannelFocused(ch)
        ctrl.enterWatch()
        assertTrue(ctrl.state.modeGeneration > modeBefore)
        assertFalse(ctrl.shouldApplyPreview(gen, ch.id, modeBefore))
        assertEquals(LiveUiMode.WATCH, ctrl.state.uiMode)
        assertFalse(ctrl.state.chromeVisible)
    }

    @Test
    fun playingChannelCommitsOnlyAfterFirstFrame() {
        val ctrl = LiveSessionController()
        val ch = channel("东南卫视")
        ctrl.markBrowseReady()
        ctrl.onChannelFocused(ch)
        ctrl.beginSwitch(ch, streamIndex = 0)

        assertEquals(ch.id, ctrl.state.previewChannelId)
        assertNull(ctrl.state.playingChannelId)
        assertFalse(ctrl.state.firstFrameRendered)
        assertFalse(ctrl.alreadyShowing(ch.id, 0))

        ctrl.onFirstFrameRendered()
        assertEquals(ch.id, ctrl.state.playingChannelId)
        assertTrue(ctrl.state.firstFrameRendered)
        assertTrue(ctrl.alreadyShowing(ch.id, 0))
    }

    @Test
    fun watchKeysReturnToBrowseKeepsFocusOnPlayingChannel() {
        val ctrl = LiveSessionController()
        val ch = channel("东南卫视")
        ctrl.onChannelFocused(ch)
        ctrl.beginSwitch(ch, streamIndex = 0)
        ctrl.onFirstFrameRendered()
        ctrl.enterWatch()
        ctrl.revealBrowseFromWatch()

        assertEquals(LiveUiMode.BROWSE, ctrl.state.uiMode)
        assertTrue(ctrl.state.chromeVisible)
        assertEquals(1f, ctrl.state.volume)
        assertEquals(ch.id, ctrl.state.focusedChannelId)
        assertEquals(ch.id, ctrl.state.playingChannelId)
    }

    @Test
    fun selectionSyncResolvesGroupForPlayingChannel() {
        val groups = listOf(
            LiveGroup("央视频道", listOf(channel("CCTV-1", "央视频道"))),
            LiveGroup("港澳台", listOf(channel("台视新闻", "港澳台"))),
        )
        assertEquals("港澳台", LiveSelectionSync.groupNameForChannel(groups, "港澳台|台视新闻"))
        assertNull(LiveSelectionSync.groupNameForChannel(groups, "missing"))
    }

    @Test
    fun streamFailoverAdvancesUntilExhausted() {
        val urls = listOf("https://a/1", "https://a/2", "https://a/3")
        assertEquals(1, LiveStreamFailover.nextIndex(0, urls.size))
        assertEquals(2, LiveStreamFailover.nextIndex(1, urls.size))
        assertNull(LiveStreamFailover.nextIndex(2, urls.size))
        assertNull(LiveStreamFailover.nextIndex(0, 0))
    }
}
