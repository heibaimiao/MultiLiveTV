package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.net.RequestGeneration
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class RequestGenerationTest {
    @Test
    fun staleSearchMustNotOverwriteNewerResults() {
        val generation = RequestGeneration()
        val first = generation.next()
        val second = generation.next()
        assertFalse(generation.shouldApply(first))
        assertTrue(generation.shouldApply(second))
    }

    @Test
    fun currentGenerationStillOwnsBusyFlagAfterCancel() {
        val generation = RequestGeneration()
        val token = generation.next()
        var loading = true
        if (generation.shouldApply(token)) loading = false
        assertEquals(false, loading)
    }
}
