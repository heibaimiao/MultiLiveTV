package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.parser.EpisodePaging
import kotlin.test.Test
import kotlin.test.assertEquals

class EpisodePagingTest {
    @Test
    fun movieHasSinglePage() {
        val pages = EpisodePaging.pages(1)
        assertEquals(listOf("1-1"), pages.map { it.label })
        assertEquals(listOf("正片"), EpisodePaging.slice(listOf("正片"), pages.single()))
    }

    @Test
    fun longSeriesSplitsIntoRanges() {
        val pages = EpisodePaging.pages(86, pageSize = 40)
        assertEquals(listOf("1-40", "41-80", "81-86"), pages.map { it.label })
        val names = (1..86).map { "第${it}集" }
        assertEquals(40, EpisodePaging.slice(names, pages[0]).size)
        assertEquals("第41集", EpisodePaging.slice(names, pages[1]).first())
        assertEquals(listOf("第81集", "第86集"), listOf(
            EpisodePaging.slice(names, pages[2]).first(),
            EpisodePaging.slice(names, pages[2]).last(),
        ))
    }
}
