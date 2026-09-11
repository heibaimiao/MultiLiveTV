package com.heibaimiao.multilivetv.home

import com.heibaimiao.multilivetv.category.CategoryMatch
import com.heibaimiao.multilivetv.category.CategoryTree
import com.heibaimiao.multilivetv.category.CategoryTreeBuilder
import com.heibaimiao.multilivetv.category.UnifiedCategories
import com.heibaimiao.multilivetv.model.VodItem

data class HomeLaunchPayload(
    val categoryTree: CategoryTree,
    val selectedSlug: String?,
    val snapshot: HomeFeedSnapshot,
)

object HomeLaunch {
    data class ListPage(
        val items: List<VodItem>,
        val page: Int,
        val pageCount: Int,
    )

    fun makePayload(
        tree: CategoryTree,
        items: List<VodItem>,
        page: Int,
        pageCount: Int,
        selectedSlug: String?,
        tvDisplay: Boolean,
    ): HomeLaunchPayload {
        val matched = CategoryMatch.filter(items, selectedSlug, tree)
        val pool = HomeFeed.replaceFirstPage(matched)
        val displayCount = if (tvDisplay) {
            minOf(HomeFeed.ALL_ROW_SIZE, pool.size)
        } else {
            HomeFeed.initialDisplayCount(pool.size)
        }
        return HomeLaunchPayload(
            categoryTree = tree,
            selectedSlug = selectedSlug,
            snapshot = HomeFeedSnapshot(
                pool = pool,
                displayCount = displayCount,
                apiPage = page,
                pageCount = maxOf(pageCount, 1),
            ),
        )
    }

    suspend fun load(
        fetchList: suspend (String?) -> ListPage,
        tvDisplay: Boolean,
    ): HomeLaunchPayload {
        val tree = UnifiedCategories.tree()
        val slug = CategoryTreeBuilder.defaultSlug(tree) ?: UnifiedCategories.defaultSlug
        val page = fetchList(slug)
        return makePayload(tree, page.items, page.page, page.pageCount, slug, tvDisplay)
    }
}
