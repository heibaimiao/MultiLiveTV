package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.ui.HomeFocusPolicy
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HomeFocusPolicyTest {
    @Test
    fun downIsConsumedOnlyWhenMoveSucceeded() {
        assertTrue(HomeFocusPolicy.shouldConsumeDirectionDown(movedToPoster = true))
        assertFalse(HomeFocusPolicy.shouldConsumeDirectionDown(movedToPoster = false))
    }

    @Test
    fun restorePrefersLastPosterThenFallsBackToFirst() {
        val ids = listOf("a", "b", "c")
        assertEquals("b", HomeFocusPolicy.restoreTargetId(ids, preferredId = "b"))
        assertEquals("a", HomeFocusPolicy.restoreTargetId(ids, preferredId = "missing"))
        assertEquals("a", HomeFocusPolicy.restoreTargetId(ids, preferredId = null))
    }

    @Test
    fun emptyListNeverRequestsPosterFocus() {
        assertNull(HomeFocusPolicy.restoreTargetId(emptyList(), preferredId = "a"))
        assertFalse(HomeFocusPolicy.canRequestPosterFocus(itemCount = 0, loadingEmpty = false))
        assertFalse(HomeFocusPolicy.canRequestPosterFocus(itemCount = 10, loadingEmpty = true))
        assertTrue(HomeFocusPolicy.canRequestPosterFocus(itemCount = 10, loadingEmpty = false))
        assertFalse(HomeFocusPolicy.canRequestPosterFocus(itemCount = 10, loadingEmpty = false, refreshing = true))
    }
}
