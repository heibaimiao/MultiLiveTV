package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.live.LiveOsdPolicy
import com.heibaimiao.multilivetv.live.LivePlayerPresentation
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LiveOsdPolicyTest {
    @Test
    fun switchLabelTrimsChannelName() {
        assertEquals("北京卫视4K", LiveOsdPolicy.switchLabel("  北京卫视4K  "))
    }

    @Test
    fun watchModeClearsChannelOsd() {
        assertEquals("", LiveOsdPolicy.watchLabel())
        assertEquals("", LiveOsdPolicy.visibleLabel("TC", watching = true))
        assertEquals("北京卫视4K", LiveOsdPolicy.visibleLabel("北京卫视4K", watching = false))
    }

    @Test
    fun hideAfterDelayOnlyIfLabelUnchanged() {
        assertTrue(LiveOsdPolicy.shouldHide("北京卫视4K", "北京卫视4K"))
        assertFalse(LiveOsdPolicy.shouldHide("东南卫视", "北京卫视4K"))
        assertFalse(LiveOsdPolicy.shouldHide("", "北京卫视4K"))
        assertFalse(LiveOsdPolicy.shouldHide("北京卫视4K", ""))
    }

    @Test
    fun autoHideUses2400ms() {
        assertEquals(2_400L, LiveOsdPolicy.AUTO_HIDE_MS)
    }

    @Test
    fun livePlayerCoversScreenAndHidesTextTracks() {
        assertTrue(LivePlayerPresentation.fillScreen)
        assertFalse(LivePlayerPresentation.showTextTracks)
    }
}
