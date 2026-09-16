package com.heibaimiao.multilivetv.parser

object EpisodePaging {
    const val PAGE_SIZE = 40

    data class Page(
        val start: Int,
        val endInclusive: Int,
        val label: String,
    )

    fun pages(count: Int, pageSize: Int = PAGE_SIZE): List<Page> {
        if (count <= 0) return emptyList()
        val size = pageSize.coerceAtLeast(1)
        return (0 until count step size).map { start ->
            val end = minOf(start + size - 1, count - 1)
            Page(start, end, "${start + 1}-${end + 1}")
        }
    }

    fun <T> slice(items: List<T>, page: Page): List<T> {
        if (items.isEmpty()) return emptyList()
        val start = page.start.coerceIn(0, items.lastIndex)
        val end = (page.endInclusive + 1).coerceIn(start + 1, items.size)
        return items.subList(start, end)
    }
}
