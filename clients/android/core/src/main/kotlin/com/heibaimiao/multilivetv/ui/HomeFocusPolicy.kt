package com.heibaimiao.multilivetv.ui

/**
 * Pure focus decisions for the TV home poster/category loop.
 * Kept free of Compose so JVM tests can lock the Down-key contract.
 */
object HomeFocusPolicy {
    /** Only consume DirectionDown when the manual move into posters succeeded. */
    fun shouldConsumeDirectionDown(movedToPoster: Boolean): Boolean = movedToPoster

    /**
     * Prefer the last opened poster when it is still in the list; otherwise the first item.
     * Empty list → null (do not request focus on a missing node).
     */
    fun restoreTargetId(itemIds: List<String>, preferredId: String?): String? {
        if (itemIds.isEmpty()) return null
        if (preferredId != null && preferredId in itemIds) return preferredId
        return itemIds.first()
    }

    /**
     * Whether the home grid is ready for a programmatic poster focus request.
     * Skip while the empty-pool first load is showing, or while a category refresh overlay is up
     * (focus should stay on the category chip).
     */
    fun canRequestPosterFocus(
        itemCount: Int,
        loadingEmpty: Boolean,
        refreshing: Boolean = false,
    ): Boolean = itemCount > 0 && !loadingEmpty && !refreshing
}
