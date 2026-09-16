package com.heibaimiao.multilivetv.ui

import com.heibaimiao.multilivetv.category.CategoryTree
import com.heibaimiao.multilivetv.category.SlugCategory

object HomeRefreshStatus {
    fun loadingMessage(): String = "正在加载影视…"

    fun refreshMessage(categoryLabel: String?): String {
        val label = categoryLabel?.trim().orEmpty()
        return if (label.isEmpty()) "正在刷新影视…" else "正在刷新「$label」…"
    }

    fun selectedCategoryLabel(
        tree: CategoryTree,
        selectedSlug: String?,
        secondary: List<SlugCategory>,
        parentSlug: String?,
    ): String? {
        val slug = selectedSlug ?: return "全部"
        // Secondary "全部" chip uses parentSlug; prefer primary label (e.g. 电影).
        secondary.firstOrNull { it.slug == slug }?.label?.let { return it }
        tree.primary.firstOrNull { it.slug == slug }?.label?.let { return it }
        tree.childrenByParent.values.asSequence().flatten().firstOrNull { it.slug == slug }?.label?.let { return it }
        if (parentSlug != null && slug == parentSlug) return "全部"
        return null
    }
}
