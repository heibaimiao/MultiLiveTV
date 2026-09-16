package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.player.VodPlayerHud
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class VodPlayerHudTest {
    @Test
    fun progressBarOnlyWhenDurationKnown() {
        assertFalse(VodPlayerHud.showProgressBar(0L))
        assertFalse(VodPlayerHud.showProgressBar(-1L))
        assertTrue(VodPlayerHud.showProgressBar(1L))
        assertTrue(VodPlayerHud.showProgressBar(90_000L))
    }

    @Test
    fun autoHideOnlyWhilePlayingAndIdle() {
        assertTrue(VodPlayerHud.shouldAutoHide(visible = true, playing = true, seeking = false))
        assertFalse(VodPlayerHud.shouldAutoHide(visible = true, playing = false, seeking = false))
        assertFalse(VodPlayerHud.shouldAutoHide(visible = true, playing = true, seeking = true))
        assertFalse(VodPlayerHud.shouldAutoHide(visible = false, playing = true, seeking = false))
        assertEquals(3_200L, VodPlayerHud.AUTO_HIDE_MS)
    }

    @Test
    fun backHidesHudBeforeExiting() {
        assertEquals(VodPlayerHud.BackAction.Hide, VodPlayerHud.onBack(visible = true))
        assertEquals(VodPlayerHud.BackAction.Exit, VodPlayerHud.onBack(visible = false))
    }

    @Test
    fun seekByClampsToDuration() {
        assertEquals(10_000L, VodPlayerHud.seekBy(0L, 90_000L, 10_000L))
        assertEquals(0L, VodPlayerHud.seekBy(5_000L, 90_000L, -10_000L))
        assertEquals(90_000L, VodPlayerHud.seekBy(85_000L, 90_000L, 10_000L))
        assertEquals(40_000L, VodPlayerHud.seekBy(40_000L, 0L, 10_000L))
    }

    @Test
    fun holdAcceleratesSeekStep() {
        assertEquals(10_000L, VodPlayerHud.holdStepMs(0L))
        assertEquals(10_000L, VodPlayerHud.holdStepMs(1_499L))
        assertEquals(30_000L, VodPlayerHud.holdStepMs(1_500L))
        assertEquals(30_000L, VodPlayerHud.holdStepMs(2_999L))
        assertEquals(60_000L, VodPlayerHud.holdStepMs(3_000L))
    }

    @Test
    fun progressFractionClamps() {
        assertEquals(0f, VodPlayerHud.progressFraction(0L, 100_000L))
        assertEquals(0.5f, VodPlayerHud.progressFraction(50_000L, 100_000L))
        assertEquals(1f, VodPlayerHud.progressFraction(120_000L, 100_000L))
        assertEquals(0f, VodPlayerHud.progressFraction(20_000L, 0L))
    }

    @Test
    fun formatClockPadsMinutesAndUsesHoursFromDuration() {
        assertEquals("00:00", VodPlayerHud.formatClock(0L, durationMs = 90_000L))
        assertEquals("00:14", VodPlayerHud.formatClock(14_000L, durationMs = 90_000L))
        assertEquals("00:00:14", VodPlayerHud.formatClock(14_000L, durationMs = 5_310_000L))
        assertEquals("01:28:30", VodPlayerHud.formatClock(5_310_000L, durationMs = 5_310_000L))
    }

    @Test
    fun bufferedFractionClampsAndIgnoresUnknownDuration() {
        assertEquals(0f, VodPlayerHud.bufferedFraction(bufferedMs = 0L, durationMs = 100_000L))
        assertEquals(0.7f, VodPlayerHud.bufferedFraction(bufferedMs = 70_000L, durationMs = 100_000L))
        assertEquals(1f, VodPlayerHud.bufferedFraction(bufferedMs = 120_000L, durationMs = 100_000L))
        assertEquals(0f, VodPlayerHud.bufferedFraction(bufferedMs = 20_000L, durationMs = 0L))
        assertEquals(0f, VodPlayerHud.bufferedFraction(bufferedMs = -1L, durationMs = 100_000L))
    }

    @Test
    fun exoDefaultBufferIsInvisibleOnFeatureLength() {
        val durationMs = 5_310_000L
        assertTrue(VodPlayerHud.bufferedFraction(50_000L, durationMs) < 0.02f)
        assertTrue(VodPlayerHud.MAX_BUFFER_MS >= 300_000L)
        assertTrue(VodPlayerHud.MIN_BUFFER_MS >= 120_000L)
        assertTrue(VodPlayerHud.MIN_BUFFER_MS <= VodPlayerHud.MAX_BUFFER_MS)
        assertTrue(VodPlayerHud.bufferedFraction(VodPlayerHud.MAX_BUFFER_MS.toLong(), durationMs) >= 0.05f)
    }

    @Test
    fun thumbOffsetStaysInsideTrack() {
        assertEquals(0f, VodPlayerHud.thumbOffsetPx(fraction = 0f, widthPx = 200f, thumbSizePx = 16f))
        assertEquals(184f, VodPlayerHud.thumbOffsetPx(fraction = 1f, widthPx = 200f, thumbSizePx = 16f))
        assertEquals(92f, VodPlayerHud.thumbOffsetPx(fraction = 0.5f, widthPx = 200f, thumbSizePx = 16f))
    }
}
