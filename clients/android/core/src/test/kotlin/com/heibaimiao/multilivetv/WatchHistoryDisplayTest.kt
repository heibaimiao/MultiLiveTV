package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.history.WatchHistoryDisplay
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WatchHistoryDisplayTest {
    @Test
    fun resumeCopyIsContinueWatchingNotAQuestion() {
        assertEquals("接着看", WatchHistoryDisplay.heading())
        assertEquals("从 0:04 继续", WatchHistoryDisplay.continueAction("0:04"))
        assertEquals("从头播放", WatchHistoryDisplay.restartAction())
    }

    @Test
    fun episodeLineDropsQualityTagsAndDuplicates() {
        assertNull(WatchHistoryDisplay.episodeLine("保镖恋人", "HD"))
        assertNull(WatchHistoryDisplay.episodeLine("保镖恋人", "1080P"))
        assertNull(WatchHistoryDisplay.episodeLine("保镖恋人", "4K"))
        assertNull(WatchHistoryDisplay.episodeLine("保镖恋人", "保镖恋人"))
        assertNull(WatchHistoryDisplay.episodeLine("保镖恋人", "  "))
        assertNull(WatchHistoryDisplay.episodeLine("保镖恋人", "正片"))
        assertNull(WatchHistoryDisplay.episodeLine("保镖恋人", "预告"))
        assertNull(WatchHistoryDisplay.episodeLine("保镖恋人", "花絮"))
        assertEquals("第12集", WatchHistoryDisplay.episodeLine("保镖恋人", "第12集"))
        assertEquals("HD第12集", WatchHistoryDisplay.episodeLine("保镖恋人", "HD第12集"))
    }

    @Test
    fun playingVideoHasNoEpisodeOverlay() {
        assertFalse(WatchHistoryDisplay.showPlayingOverlay)
    }

    @Test
    fun progressBarOnlyWhenDurationKnown() {
        assertTrue(WatchHistoryDisplay.showProgressBar(7_200_000L))
        assertFalse(WatchHistoryDisplay.showProgressBar(0L))
        assertFalse(WatchHistoryDisplay.showProgressBar(-1L))
    }
}
