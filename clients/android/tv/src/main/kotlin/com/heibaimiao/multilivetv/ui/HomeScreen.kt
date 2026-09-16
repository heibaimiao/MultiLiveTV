package com.heibaimiao.multilivetv.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Card
import androidx.tv.material3.Text
import coil.compose.AsyncImage
import com.heibaimiao.multilivetv.HomeViewModel
import com.heibaimiao.multilivetv.model.VodItem
import kotlinx.coroutines.flow.distinctUntilChanged

@Composable
fun HomeScreen(
    viewModel: HomeViewModel,
    sidebarHomeFocus: FocusRequester,
    restorePosterId: String? = null,
    onPosterRestored: () -> Unit = {},
    onOpen: (VodItem) -> Unit,
) {
    val state by viewModel.state.collectAsState()
    val categoryLandingFocus = remember { FocusRequester() }
    val posterFocusById = remember { mutableMapOf<String, FocusRequester>() }
    var gridFocused by remember { mutableStateOf(false) }
    var pendingPosterFocus by remember { mutableStateOf(true) }
    var postersAttached by remember { mutableStateOf(false) }

    val categoryLabel = remember(state.selectedSlug, state.tree, state.secondary, state.parentSlug) {
        HomeRefreshStatus.selectedCategoryLabel(
            tree = state.tree,
            selectedSlug = state.selectedSlug,
            secondary = state.secondary,
            parentSlug = state.parentSlug,
        )
    }

    fun requesterFor(id: String): FocusRequester =
        posterFocusById.getOrPut(id) { FocusRequester() }

    fun tryFocusPoster(preferredId: String?): Boolean {
        val ids = state.visible.map { it.id }
        val loadingEmpty = state.loading && state.pool.isEmpty()
        if (!HomeFocusPolicy.canRequestPosterFocus(ids.size, loadingEmpty, state.refreshing)) return false
        val targetId = HomeFocusPolicy.restoreTargetId(ids, preferredId) ?: return false
        return try {
            requesterFor(targetId).requestFocus()
            true
        } catch (_: IllegalStateException) {
            false
        }
    }

    fun retryCurrent() {
        if (state.tree.primary.isEmpty()) {
            viewModel.bootstrap()
        } else {
            viewModel.selectCategory(state.selectedSlug)
        }
    }

    BackHandler(enabled = gridFocused) {
        runCatching { categoryLandingFocus.requestFocus() }
    }

    LaunchedEffect(state.selectedSlug) {
        pendingPosterFocus = true
        postersAttached = false
    }

    LaunchedEffect(restorePosterId) {
        if (restorePosterId != null) {
            pendingPosterFocus = true
        }
    }

    LaunchedEffect(state.refreshing) {
        if (state.refreshing) {
            pendingPosterFocus = false
            runCatching { categoryLandingFocus.requestFocus() }
        } else if (state.error == null && state.visible.isNotEmpty()) {
            pendingPosterFocus = true
        }
    }

    LaunchedEffect(
        pendingPosterFocus,
        restorePosterId,
        postersAttached,
        state.visible.map { it.id },
        state.loading,
        state.refreshing,
        state.pool.size,
    ) {
        if (state.refreshing) return@LaunchedEffect
        if (!pendingPosterFocus && restorePosterId == null) return@LaunchedEffect
        val loadingEmpty = state.loading && state.pool.isEmpty()
        if (!HomeFocusPolicy.canRequestPosterFocus(state.visible.size, loadingEmpty, state.refreshing)) {
            return@LaunchedEffect
        }
        if (!postersAttached) return@LaunchedEffect

        val preferred = restorePosterId
        repeat(5) {
            withFrameNanos { }
            if (tryFocusPoster(preferred)) {
                pendingPosterFocus = false
                if (restorePosterId != null) onPosterRestored()
                return@LaunchedEffect
            }
        }
    }

    Column(Modifier.fillMaxSize().background(AppTheme.screenBackground)) {
        CategoryTabs(
            primary = state.tree.primary,
            secondary = state.secondary,
            activeSlug = state.selectedSlug,
            activeParentSlug = state.parentSlug,
            onSelect = viewModel::selectCategory,
            landingFocusRequester = categoryLandingFocus,
            onMoveDownToContent = {
                val moved = tryFocusPoster(restorePosterId)
                if (!moved) pendingPosterFocus = true
                moved
            },
            onBackToSidebar = { runCatching { sidebarHomeFocus.requestFocus() } },
        )
        Box(
            Modifier
                .weight(1f)
                .fillMaxSize()
                .onFocusChanged { gridFocused = it.hasFocus },
        ) {
            when {
                state.loading && state.pool.isEmpty() -> {
                    postersAttached = false
                    Centered {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator(color = AppTheme.accent)
                            Spacer(Modifier.height(16.dp))
                            StatusText(HomeRefreshStatus.loadingMessage())
                        }
                    }
                }
                state.error != null && state.pool.isEmpty() -> {
                    postersAttached = false
                    Centered {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            StatusText(state.error!!)
                            Spacer(Modifier.height(12.dp))
                            TvAction("重试", ::retryCurrent)
                        }
                    }
                }
                state.visible.isEmpty() -> {
                    postersAttached = false
                    Centered { StatusText("暂无内容") }
                }
                else -> VodPosterGrid(
                    items = state.visible,
                    onClick = onOpen,
                    onLoadMore = viewModel::loadMore,
                    loadingMore = state.loadingMore,
                    interactionEnabled = !state.refreshing,
                    focusRequesterFor = ::requesterFor,
                    preferredFocusId = HomeFocusPolicy.restoreTargetId(
                        state.visible.map { it.id },
                        restorePosterId,
                    ),
                    onPosterNodesAttached = { postersAttached = true },
                )
            }

            if (state.error != null && state.pool.isNotEmpty() && !state.refreshing) {
                SoftErrorBanner(
                    message = state.error!!,
                    onRetry = ::retryCurrent,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .padding(AppTheme.screenPadding),
                )
            }

            if (state.refreshing && state.pool.isNotEmpty()) {
                PosterRefreshOverlay(
                    message = HomeRefreshStatus.refreshMessage(categoryLabel),
                )
            }
        }
    }
}

@Composable
private fun PosterRefreshOverlay(message: String) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.55f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator(color = AppTheme.accent)
            Spacer(Modifier.height(16.dp))
            StatusText(message)
        }
    }
}

@Composable
private fun SoftErrorBanner(
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .background(Color.Black.copy(alpha = 0.72f))
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        StatusText(message)
        Spacer(Modifier.height(8.dp))
        TvAction("重试", onRetry)
    }
}

@Composable
fun VodPosterGrid(
    items: List<VodItem>,
    onClick: (VodItem) -> Unit,
    onLoadMore: (() -> Unit)? = null,
    loadingMore: Boolean = false,
    interactionEnabled: Boolean = true,
    focusRequesterFor: (String) -> FocusRequester,
    preferredFocusId: String? = null,
    onPosterNodesAttached: () -> Unit = {},
) {
    val gridState = rememberLazyGridState()
    if (onLoadMore != null) {
        LaunchedEffect(gridState, items.size, loadingMore) {
            snapshotFlow {
                val info = gridState.layoutInfo
                val last = info.visibleItemsInfo.lastOrNull()?.index ?: 0
                val total = info.totalItemsCount
                total > 0 && last >= total - 3
            }
                .distinctUntilChanged()
                .collect { nearEnd ->
                    if (nearEnd && !loadingMore) onLoadMore()
                }
        }
    }
    LaunchedEffect(items.map { it.id }, preferredFocusId) {
        withFrameNanos { }
        onPosterNodesAttached()
    }
    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 168.dp),
        state = gridState,
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(AppTheme.screenPadding),
        horizontalArrangement = Arrangement.spacedBy(AppTheme.gridSpacing),
        verticalArrangement = Arrangement.spacedBy(AppTheme.gridSpacing),
    ) {
        itemsIndexed(items, key = { _, item -> item.id }) { _, item ->
            Card(
                onClick = { if (interactionEnabled) onClick(item) },
                modifier = Modifier
                    .focusRequester(focusRequesterFor(item.id))
                    .focusProperties { canFocus = interactionEnabled },
            ) {
                Column {
                    AsyncImage(
                        model = item.vodPic.ifEmpty { null },
                        contentDescription = item.vodName,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxWidth().aspectRatio(2f / 3f),
                    )
                    Text(
                        item.vodName,
                        color = AppTheme.textPrimary,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(10.dp),
                    )
                }
            }
        }
        if (loadingMore) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                StatusText("加载更多…")
            }
        }
    }
}
