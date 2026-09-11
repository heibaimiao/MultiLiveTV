package com.heibaimiao.multilivetv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.heibaimiao.multilivetv.HomeViewModel
import com.heibaimiao.multilivetv.model.VodItem

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(viewModel: HomeViewModel, onOpen: (VodItem) -> Unit) {
    val state by viewModel.state.collectAsState()
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
                state.loading && state.pool.isEmpty() -> Centered { CircularProgressIndicator(color = AppTheme.accent) }
                state.error != null && state.pool.isEmpty() -> Centered {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(state.error!!, color = AppTheme.textSecondary)
                        Button(onClick = viewModel::bootstrap, modifier = Modifier.padding(AppTheme.screenPadding)) {
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
                    VodPosterGrid(
                        items = state.visible,
                        onClick = onOpen,
                        onLoadMore = viewModel::loadMore,
                        loadingMore = state.loadingMore,
                    )
                }
            }
        }
    }
}

@Composable
fun Centered(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center, content = { content() })
}
