package com.heibaimiao.multilivetv.player

object VodPlayerHud {
    const val AUTO_HIDE_MS = 3_200L
    const val STEP_MS = 10_000L
    const val MIN_BUFFER_MS = 180_000
    const val MAX_BUFFER_MS = 360_000
    const val PLAYBACK_BUFFER_MS = 2_500
    const val REBUFFER_MS = 5_000

    enum class BackAction { Hide, Exit }

    fun showProgressBar(durationMs: Long): Boolean = durationMs > 0L

    fun shouldAutoHide(visible: Boolean, playing: Boolean, seeking: Boolean): Boolean =
        visible && playing && !seeking

    fun onBack(visible: Boolean): BackAction =
        if (visible) BackAction.Hide else BackAction.Exit

    fun seekBy(positionMs: Long, durationMs: Long, deltaMs: Long): Long {
        val position = positionMs.coerceAtLeast(0L)
        if (durationMs <= 0L) return position
        return (position + deltaMs).coerceIn(0L, durationMs)
    }

    fun holdStepMs(holdElapsedMs: Long): Long = when {
        holdElapsedMs < 1_500L -> STEP_MS
        holdElapsedMs < 3_000L -> 30_000L
        else -> 60_000L
    }

    fun holdIntervalMs(holdElapsedMs: Long): Long = when {
        holdElapsedMs < 1_500L -> 350L
        holdElapsedMs < 3_000L -> 280L
        else -> 220L
    }

    fun progressFraction(positionMs: Long, durationMs: Long): Float {
        if (durationMs <= 0L) return 0f
        return (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f)
    }

    fun bufferedFraction(bufferedMs: Long, durationMs: Long): Float {
        if (bufferedMs < 0L) return 0f
        return progressFraction(bufferedMs, durationMs)
    }

    fun formatClock(positionMs: Long, durationMs: Long = positionMs): String {
        val totalSec = (positionMs / 1000L).coerceAtLeast(0L)
        val hours = totalSec / 3600L
        val minutes = (totalSec % 3600L) / 60L
        val seconds = totalSec % 60L
        val showHours = durationMs >= 3_600_000L
        val mm = minutes.toString().padStart(2, '0')
        val ss = seconds.toString().padStart(2, '0')
        return if (showHours) {
            "${hours.toString().padStart(2, '0')}:$mm:$ss"
        } else {
            "$mm:$ss"
        }
    }

    fun thumbOffsetPx(fraction: Float, widthPx: Float, thumbSizePx: Float): Float {
        if (widthPx <= 0f || thumbSizePx <= 0f) return 0f
        val center = widthPx * fraction.coerceIn(0f, 1f)
        val maxOffset = (widthPx - thumbSizePx).coerceAtLeast(0f)
        return (center - thumbSizePx / 2f).coerceIn(0f, maxOffset)
    }
}
