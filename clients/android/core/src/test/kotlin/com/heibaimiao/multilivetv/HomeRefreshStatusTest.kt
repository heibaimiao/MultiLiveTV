package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.category.CategoryTree
import com.heibaimiao.multilivetv.category.SlugCategory
import com.heibaimiao.multilivetv.ui.HomeRefreshStatus
import kotlin.test.Test
import kotlin.test.assertEquals

class HomeRefreshStatusTest {
    @Test
    fun loadingAndRefreshCopy() {
        assertEquals("正在加载影视…", HomeRefreshStatus.loadingMessage())
        assertEquals("正在刷新影视…", HomeRefreshStatus.refreshMessage(null))
        assertEquals("正在刷新影视…", HomeRefreshStatus.refreshMessage("  "))
        assertEquals("正在刷新「动作片」…", HomeRefreshStatus.refreshMessage("动作片"))
    }

    @Test
    fun resolvesCategoryLabelFromTree() {
        val tree = CategoryTree(
            all = listOf(SlugCategory("movie", "电影"), SlugCategory("action", "动作片")),
            primary = listOf(SlugCategory("movie", "电影")),
            childrenByParent = mapOf("movie" to listOf(SlugCategory("action", "动作片"))),
        )
        assertEquals("全部", HomeRefreshStatus.selectedCategoryLabel(tree, null, emptyList(), null))
        assertEquals(
            "动作片",
            HomeRefreshStatus.selectedCategoryLabel(
                tree,
                selectedSlug = "action",
                secondary = listOf(SlugCategory("action", "动作片")),
                parentSlug = "movie",
            ),
        )
        assertEquals(
            "电影",
            HomeRefreshStatus.selectedCategoryLabel(
                tree,
                selectedSlug = "movie",
                secondary = listOf(SlugCategory("action", "动作片")),
                parentSlug = "movie",
            ),
        )
    }
}
