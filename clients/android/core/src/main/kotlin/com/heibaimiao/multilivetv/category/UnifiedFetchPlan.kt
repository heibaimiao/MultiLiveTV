package com.heibaimiao.multilivetv.category

object UnifiedFetchPlan {
    const val MAX_IN_FLIGHT = 6
    const val PARENT_SOURCE_LIMIT = 2
    const val LEAF_SOURCE_LIMIT = 3
    const val PER_CALL_TIMEOUT_MS = 5_000L
    const val FIRST_PAINT_MS = 4_000L
    const val LEAF_MIN_PAGES = 1
    const val PARENT_MIN_PAGES = 2

    data class Request(val sourceId: Int, val typeId: Int?)

    fun requests(
        slug: String?,
        sourceIdsByPriority: List<Int>,
        typeIdsFor: (String, Int) -> List<Int> = UnifiedCategories::listTypeIds,
    ): List<Request> {
        if (slug == null) {
            return sourceIdsByPriority.take(LEAF_SOURCE_LIMIT).map { Request(it, null) }
        }
        val expanded = sourceIdsByPriority.mapNotNull { sourceId ->
            val ids = typeIdsFor(slug, sourceId)
            if (ids.isEmpty()) null else sourceId to ids
        }
        val parent = expanded.any { it.second.size > 1 }
        val limited = expanded.take(if (parent) PARENT_SOURCE_LIMIT else LEAF_SOURCE_LIMIT)
        return limited.flatMap { (sourceId, ids) -> ids.map { Request(sourceId, it) } }
    }

    fun minCompletedPages(plan: List<Request>): Int {
        val parent = plan.groupBy { it.sourceId }.any { it.value.size > 1 }
        return if (parent) PARENT_MIN_PAGES else LEAF_MIN_PAGES
    }
}
