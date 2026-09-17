package com.heibaimiao.multilivetv.home

import com.heibaimiao.multilivetv.model.VodItem

object HomeFeed {
    const val FETCH_SIZE = 50
    const val INITIAL_DISPLAY = 30
    const val SCROLL_LOAD_SIZE = 20
    const val HOT_SIZE = 6
    const val RECENT_SIZE = 6
    const val ALL_ROW_SIZE = 6

    sealed class ContentPhase {
        data object Loading : ContentPhase()
        data class Error(val message: String) : ContentPhase()
        data object Empty : ContentPhase()
        data object Content : ContentPhase()
    }

    sealed class LoadMoreAction {
        data class Reveal(val displayCount: Int) : LoadMoreAction()
        data class Fetch(val page: Int) : LoadMoreAction()
        data object Idle : LoadMoreAction()
    }

    private val trailingYear = Regex("""(?:19|20)\d{2}$""")
    private val trailingYearDisplay = Regex("""[\s\(（]*((?:19|20)\d{2})[年\)）]*$""")

    fun normalizeTitle(name: String): String =
        name.trim().lowercase()
            .replace(Regex("""\s+"""), "")
            .replace(Regex("""[·・:：\-\—_]"""), "")

    fun titleKeyForMatch(name: String): String =
        normalizeTitle(name).replace(trailingYear, "")

    fun searchKeyword(name: String): String {
        val stripped = name.trim().replace(trailingYearDisplay, "")
        return stripped.ifBlank { name.trim() }
    }

    fun normalizeYear(year: String?): String {
        if (year == null) return ""
        val digits = rawYearDigits(year) ?: return ""
        val value = digits.toIntOrNull() ?: return ""
        return if (isDisplayableReleaseYear(value)) digits else ""
    }

    /**
     * Years used for ranking. Future placeholders (e.g. 2030) map to the current
     * calendar year so recently-added titles still surface with this year's films.
     */
    fun sortYearValue(year: String?, vodTime: Int = 0, nowYear: Int = currentCalendarYear()): Int {
        val digits = rawYearDigits(year)
        if (digits != null) {
            val value = digits.toIntOrNull()
            if (value != null) {
                if (value in 1900..(nowYear + 1)) return value
                if (value > nowYear + 1) return nowYear
            }
        }
        return yearFromVodTime(vodTime, fallback = 0)
    }

    fun yearValue(year: String?): Int = normalizeYear(year).toIntOrNull() ?: 0

    fun isDisplayableReleaseYear(year: Int, nowYear: Int = currentCalendarYear()): Boolean =
        year in 1900..(nowYear + 1)

    fun currentCalendarYear(): Int =
        java.util.Calendar.getInstance().get(java.util.Calendar.YEAR)

    private fun rawYearDigits(year: String?): String? {
        if (year == null) return null
        return Regex("""\d{4}""").find(year.trim())?.value
    }

    private fun yearFromVodTime(vodTime: Int, fallback: Int): Int {
        if (vodTime <= 0) return fallback
        val cal = java.util.Calendar.getInstance()
        cal.timeInMillis = vodTime * 1000L
        return cal.get(java.util.Calendar.YEAR)
    }

    fun sortByUpdatedDesc(items: List<VodItem>): List<VodItem> =
        items.mapIndexed { index, item -> index to item }
            .sortedWith(
                compareByDescending<Pair<Int, VodItem>> {
                    sortYearValue(it.second.vodYear, it.second.vodTime)
                }
                    .thenByDescending { it.second.vodTime }
                    .thenBy { it.first },
            )
            .map { it.second }

    fun mergeKey(item: VodItem): String = mergeKey(item.vodName, item.vodYear)

    fun mergeKey(title: String, year: String?): String {
        val normalized = normalizeTitle(title)
        val yearPart = normalizeYear(year)
        return if (yearPart.isEmpty()) normalized else "$normalized|$yearPart"
    }

    fun resolvePoolMergeKey(item: VodItem, existingKeys: List<String>): String {
        val title = normalizeTitle(item.vodName)
        if (title.isEmpty()) return mergeKey(item)
        val year = normalizeYear(item.vodYear)
        val bare = title
        val yeared = if (year.isEmpty()) null else "$title|$year"
        val titleKeys = existingKeys.filter { it == bare || it.startsWith("$title|") }
        if (yeared != null) {
            if (yeared in titleKeys || bare in titleKeys) return yeared
            return yeared
        }
        val yearedKeys = titleKeys.filter { it.contains("|") }
        if (yearedKeys.size == 1) return yearedKeys[0]
        if (bare in titleKeys) return bare
        return bare
    }

    fun initialDisplayCount(poolLength: Int): Int = minOf(INITIAL_DISPLAY, poolLength)

    fun nextDisplayCount(current: Int, poolLength: Int): Int =
        minOf(current + SCROLL_LOAD_SIZE, poolLength)

    fun contentPhase(isLoading: Boolean, errorMessage: String?, poolIsEmpty: Boolean): ContentPhase = when {
        isLoading && poolIsEmpty -> ContentPhase.Loading
        errorMessage != null && poolIsEmpty -> ContentPhase.Error(errorMessage)
        poolIsEmpty -> ContentPhase.Empty
        else -> ContentPhase.Content
    }

    fun nextLoadMore(
        displayCount: Int,
        poolLength: Int,
        apiPage: Int,
        pageCount: Int,
        isBusy: Boolean,
    ): LoadMoreAction {
        if (isBusy) return LoadMoreAction.Idle
        if (displayCount < poolLength) {
            return LoadMoreAction.Reveal(nextDisplayCount(displayCount, poolLength))
        }
        if (apiPage < pageCount) return LoadMoreAction.Fetch(apiPage + 1)
        return LoadMoreAction.Idle
    }

    fun replaceFirstPage(incoming: List<VodItem>): List<VodItem> =
        mergeIntoPool(emptyList(), incoming, isFirstBatch = true)

    fun mergeIntoPool(pool: List<VodItem>, incoming: List<VodItem>, isFirstBatch: Boolean): List<VodItem> {
        val orderedKeys = mutableListOf<String>()
        val map = mutableMapOf<String, VodItem>()

        fun consume(items: List<VodItem>, overwrite: Boolean) {
            for (item in items) {
                val key = resolvePoolMergeKey(item, orderedKeys)
                val bare = normalizeTitle(item.vodName)
                if (key != bare && map[bare] != null) {
                    if (map[key] == null) {
                        val existing = map[bare] ?: return@consume
                        map[key] = existing
                        if (key !in orderedKeys) orderedKeys += key
                    }
                    map.remove(bare)
                    orderedKeys.removeAll { it == bare }
                }
                if (map[key] == null) {
                    orderedKeys += key
                    map[key] = item
                } else if (overwrite) {
                    map[key] = item
                }
            }
        }

        if (isFirstBatch) {
            consume(pool, overwrite = true)
            consume(incoming, overwrite = true)
            val merged = orderedKeys.mapNotNull { map[it] }
            return sortByUpdatedDesc(merged).take(FETCH_SIZE)
        }

        consume(pool, overwrite = false)
        consume(incoming, overwrite = false)
        val seen = mutableSetOf<String>()
        val combined = mutableListOf<VodItem>()
        for (item in pool) {
            val key = resolvePoolMergeKey(item, orderedKeys)
            if (!seen.add(key)) continue
            combined += map[key] ?: item
        }
        for (key in orderedKeys) {
            if (key in seen) continue
            val item = map[key] ?: continue
            if (!seen.add(key)) continue
            combined += item
            if (combined.size >= pool.size + FETCH_SIZE) break
        }
        return sortByUpdatedDesc(combined)
    }
}

data class HomeFeedSnapshot(
    val pool: List<VodItem>,
    val displayCount: Int,
    val apiPage: Int,
    val pageCount: Int,
)

class HomeFeedCache {
    private val storage = mutableMapOf<String, HomeFeedSnapshot>()

    fun save(snapshot: HomeFeedSnapshot, slug: String?) {
        storage[key(slug)] = snapshot
    }

    fun snapshot(slug: String?): HomeFeedSnapshot? = storage[key(slug)]

    companion object {
        fun key(slug: String?): String = slug ?: "all"
    }
}
