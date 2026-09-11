package com.heibaimiao.multilivetv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.heibaimiao.multilivetv.model.VodItem
import kotlinx.coroutines.flow.distinctUntilChanged

@Composable
fun VodPosterGrid(
    items: List<VodItem>,
    onClick: (VodItem) -> Unit,
    onLoadMore: (() -> Unit)? = null,
    loadingMore: Boolean = false,
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

    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = AppTheme.cardMinWidth),
        state = gridState,
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(AppTheme.screenPadding),
        horizontalArrangement = Arrangement.spacedBy(AppTheme.gridSpacing),
        verticalArrangement = Arrangement.spacedBy(AppTheme.gridSpacing),
    ) {
        itemsIndexed(items, key = { _, item -> item.id }) { _, item ->
            VodCard(item, onClick)
        }
        if (loadingMore) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = AppTheme.accent)
                }
            }
        }
    }
}

@Composable
fun VodCard(item: VodItem, onClick: (VodItem) -> Unit) {
    Column(Modifier.clickable { onClick(item) }) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(2f / 3f)
                .clip(RoundedCornerShape(AppTheme.posterRadius))
                .background(AppTheme.elevated),
        ) {
            AsyncImage(
                model = item.vodPic.ifEmpty { null },
                contentDescription = item.vodName,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize(),
            )
            val remarks = item.displayRemarks
            if (!remarks.isNullOrEmpty()) {
                Text(
                    remarks,
                    color = Color.White,
                    fontSize = 11.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(6.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(Color.Black.copy(alpha = 0.72f))
                        .padding(horizontal = 6.dp, vertical = 3.dp),
                )
            }
        }
        Text(
            item.vodName,
            color = AppTheme.textPrimary,
            maxLines = 2,
            minLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 8.dp),
        )
        val subtitle = item.displayGenreLine
        if (!subtitle.isNullOrEmpty()) {
            Text(subtitle, color = AppTheme.textTertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}
