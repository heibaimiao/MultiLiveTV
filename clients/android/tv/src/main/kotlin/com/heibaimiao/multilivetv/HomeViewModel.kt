package com.heibaimiao.multilivetv

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.heibaimiao.multilivetv.category.CategoryMatch
import com.heibaimiao.multilivetv.category.CategoryTree
import com.heibaimiao.multilivetv.category.CategoryTreeBuilder
import com.heibaimiao.multilivetv.home.HomeFeed
import com.heibaimiao.multilivetv.home.HomeFeedCache
import com.heibaimiao.multilivetv.home.HomeFeedSnapshot
import com.heibaimiao.multilivetv.model.VodItem
import com.heibaimiao.multilivetv.net.RequestFailure
import com.heibaimiao.multilivetv.vod.VodService
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class HomeUiState(
    val tree: CategoryTree = CategoryTree.empty,
    val selectedSlug: String? = null,
    val pool: List<VodItem> = emptyList(),
    val displayCount: Int = 0,
    val apiPage: Int = 1,
    val pageCount: Int = 1,
    val loading: Boolean = true,
    val loadingMore: Boolean = false,
    val refreshing: Boolean = false,
    val error: String? = null,
) {
    val visible: List<VodItem> get() = pool.take(displayCount)
    val parentSlug: String? get() = CategoryTreeBuilder.parentSlug(tree, selectedSlug)
    val secondary get() = parentSlug?.let { tree.childrenByParent[it] }.orEmpty()
}

class HomeViewModel(private val vod: VodService) : ViewModel() {
    private val cache = HomeFeedCache()
    private var loadJob: Job? = null
    private var loadGeneration = 0
    private val _state = MutableStateFlow(HomeUiState())
    val state: StateFlow<HomeUiState> = _state

    init {
        bootstrap()
    }

    fun bootstrap() {
        loadJob?.cancel()
        loadGeneration += 1
        val generation = loadGeneration
        loadJob = viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            try {
                val launch = vod.loadHomeLaunch(tvDisplay = true)
                if (generation != loadGeneration) return@launch
                cache.save(launch.snapshot, launch.selectedSlug)
                _state.value = HomeUiState(
                    tree = launch.categoryTree,
                    selectedSlug = launch.selectedSlug,
                    pool = launch.snapshot.pool,
                    displayCount = launch.snapshot.displayCount,
                    apiPage = launch.snapshot.apiPage,
                    pageCount = launch.snapshot.pageCount,
                    loading = false,
                )
            } catch (error: Exception) {
                if (generation != loadGeneration) return@launch
                _state.update { it.copy(loading = false, error = RequestFailure.userFacingMessage(error)) }
            }
        }
    }

    fun selectCategory(slug: String?) {
        val current = _state.value
        if (slug == current.selectedSlug && current.error == null) return
        if (current.pool.isNotEmpty()) {
            cache.save(currentSnapshot(), current.selectedSlug)
        }
        loadGeneration += 1
        val generation = loadGeneration
        loadJob?.cancel()
        val cached = cache.snapshot(slug)
        if (cached != null) {
            _state.update {
                it.copy(
                    selectedSlug = slug,
                    pool = cached.pool,
                    displayCount = cached.displayCount,
                    apiPage = cached.apiPage,
                    pageCount = cached.pageCount,
                    error = null,
                    loading = false,
                    loadingMore = false,
                    refreshing = true,
                )
            }
        } else {
            _state.update {
                it.copy(
                    selectedSlug = slug,
                    pool = emptyList(),
                    displayCount = 0,
                    apiPage = 1,
                    pageCount = 1,
                    error = null,
                    loading = true,
                    loadingMore = false,
                    refreshing = false,
                )
            }
        }
        fetchPage(slug, page = 1, replace = true, generation = generation)
    }

    fun loadMore() {
        val current = _state.value
        if (current.loading || current.loadingMore || current.refreshing) return
        when (
            val action = HomeFeed.nextLoadMore(
                current.displayCount,
                current.pool.size,
                current.apiPage,
                current.pageCount,
                false,
            )
        ) {
            is HomeFeed.LoadMoreAction.Reveal -> _state.update { it.copy(displayCount = action.displayCount) }
            is HomeFeed.LoadMoreAction.Fetch -> {
                loadGeneration += 1
                fetchPage(current.selectedSlug, action.page, replace = false, generation = loadGeneration)
            }
            HomeFeed.LoadMoreAction.Idle -> Unit
        }
    }

    private fun fetchPage(slug: String?, page: Int, replace: Boolean, generation: Int) {
        loadJob = viewModelScope.launch {
            _state.update {
                it.copy(
                    selectedSlug = slug,
                    loading = replace && it.pool.isEmpty(),
                    loadingMore = !replace,
                    refreshing = replace && it.pool.isNotEmpty(),
                    error = null,
                )
            }
            try {
                val response = vod.fetchList(page = page, slug = slug)
                if (generation != loadGeneration) return@launch
                val tree = _state.value.tree
                val matched = HomeFeed.sortByUpdatedDesc(
                    CategoryMatch.filter(response.list, slug, tree),
                )
                val pool = if (replace) {
                    HomeFeed.replaceFirstPage(matched)
                } else {
                    HomeFeed.mergeIntoPool(_state.value.pool, matched, isFirstBatch = false)
                }
                val displayCount = if (replace) {
                    HomeFeed.initialDisplayCount(pool.size)
                } else {
                    minOf(_state.value.displayCount + HomeFeed.SCROLL_LOAD_SIZE, pool.size)
                }
                val snapshot = HomeFeedSnapshot(pool, displayCount, response.page, maxOf(response.pagecount, 1))
                cache.save(snapshot, slug)
                _state.update {
                    it.copy(
                        pool = pool,
                        displayCount = displayCount,
                        apiPage = snapshot.apiPage,
                        pageCount = snapshot.pageCount,
                        loading = false,
                        loadingMore = false,
                        refreshing = false,
                    )
                }
            } catch (error: Exception) {
                if (generation != loadGeneration) return@launch
                _state.update {
                    it.copy(
                        loading = false,
                        loadingMore = false,
                        refreshing = false,
                        error = RequestFailure.userFacingMessage(error),
                    )
                }
            }
        }
    }

    private fun currentSnapshot(): HomeFeedSnapshot {
        val current = _state.value
        return HomeFeedSnapshot(current.pool, current.displayCount, current.apiPage, current.pageCount)
    }
}
