package com.heibaimiao.multilivetv.parser

object PlaybackSeek {
    const val STEP_MS = 10_000L

    enum class TapZone { Rewind, Forward, Center }

    fun targetFromDrag(
        startPositionMs: Long,
        durationMs: Long,
        dragPx: Float,
        widthPx: Float,
    ): Long {
        if (durationMs <= 0L || widthPx <= 0f) return startPositionMs.coerceAtLeast(0L)
        val delta = (dragPx / widthPx) * durationMs
        return (startPositionMs + delta.toLong()).coerceIn(0L, durationMs)
    }

    fun tapZone(x: Float, width: Float): TapZone {
        if (width <= 0f) return TapZone.Center
        val ratio = x / width
        return when {
            ratio < 1f / 3f -> TapZone.Rewind
            ratio > 2f / 3f -> TapZone.Forward
            else -> TapZone.Center
        }
    }

    fun doubleTapTarget(
        positionMs: Long,
        durationMs: Long,
        zone: TapZone,
        stepMs: Long = STEP_MS,
    ): Long? = when (zone) {
        TapZone.Rewind -> (positionMs - stepMs).coerceAtLeast(0L)
        TapZone.Forward -> (positionMs + stepMs).coerceAtMost(durationMs.coerceAtLeast(0L))
        TapZone.Center -> null
    }
}
