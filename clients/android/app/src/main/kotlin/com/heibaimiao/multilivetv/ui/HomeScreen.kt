package com.heibaimiao.multilivetv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.heibaimiao.multilivetv.HomeViewModel
import com.heibaimiao.multilivetv.model.VodItem

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(viewModel: HomeViewModel, onOpen: (VodItem) -> Unit) {
    val state by viewModel.state.collectAsState()
    val categoryLabel = remember(state.selectedSlug, state.tree, state.secondary, state.parentSlug) {
        HomeRefreshStatus.selectedCategoryLabel(
            tree = state.tree,
            selectedSlug = state.selectedSlug,
            secondary = state.secondary,
            parentSlug = state.parentSlug,
        )
    }

    fun retryCurrent() {
        if (state.tree.primary.isEmpty()) {
            viewModel.bootstrap()
        } else {
            viewModel.selectCategory(state.selectedSlug)
        }
    }

    Column(Modifier.fillMaxSize().background(AppTheme.screenBackground)) {
        CategoryTabs(
            primary = state.tree.primary,
            secondary = state.secondary,
            activeSlug = state.selectedSlug,
            activeParentSlug = state.parentSlug,
            onSelect = viewModel::selectCategory,
        )
        Box(Modifier.weight(1f).fillMaxSize()) {
            when {
                state.loading && state.pool.isEmpty() -> Centered {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator(color = AppTheme.accent)
                        Spacer(Modifier.height(16.dp))
                        Text(HomeRefreshStatus.loadingMessage(), color = AppTheme.textSecondary)
                    }
                }
                state.error != null && state.pool.isEmpty() -> Centered {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(state.error!!, color = AppTheme.textSecondary)
                        Button(onClick = ::retryCurrent, modifier = Modifier.padding(AppTheme.screenPadding)) {
                            Text("重试")
                        }
                    }
                }
                state.visible.isEmpty() -> Centered { Text("暂无内容", color = AppTheme.textSecondary) }
                else -> PullToRefreshBox(
                    isRefreshing = state.refreshing,
                    onRefresh = viewModel::refresh,
                    modifier = Modifier.fillMaxSize(),
                ) {
                    Box(Modifier.fillMaxSize()) {
                        VodPosterGrid(
                            items = state.visible,
                            onClick = { if (!state.refreshing) onOpen(it) },
                            onLoadMore = viewModel::loadMore,
                            loadingMore = state.loadingMore,
                        )
                        if (state.refreshing) {
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .background(Color.Black.copy(alpha = 0.55f))
                                    .clickable(
                                        indication = null,
                                        interactionSource = remember { MutableInteractionSource() },
                                    ) { },
                                contentAlignment = Alignment.Center,
                            ) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    CircularProgressIndicator(color = AppTheme.accent)
                                    Spacer(Modifier.height(16.dp))
                                    Text(
                                        HomeRefreshStatus.refreshMessage(categoryLabel),
                                        color = AppTheme.textSecondary,
                                    )
                                }
                            }
                        }
                    }
                }
            }

            if (state.error != null && state.pool.isNotEmpty() && !state.refreshing) {
                Column(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .padding(AppTheme.screenPadding)
                        .background(Color.Black.copy(alpha = 0.72f))
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(state.error!!, color = AppTheme.textSecondary)
                    Button(onClick = ::retryCurrent, modifier = Modifier.padding(top = 8.dp)) {
                        Text("重试")
                    }
                }
            }
        }
    }
}

@Composable
fun Centered(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center, content = { content() })
}
