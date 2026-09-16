package com.heibaimiao.multilivetv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import coil.compose.AsyncImage
import com.heibaimiao.multilivetv.history.VodPlaybackRequest
import com.heibaimiao.multilivetv.history.WatchHistoryProgress
import com.heibaimiao.multilivetv.history.WatchHistoryRecord
import com.heibaimiao.multilivetv.history.WatchHistoryResume
import com.heibaimiao.multilivetv.history.WatchHistoryStore
import com.heibaimiao.multilivetv.net.RequestFailure
import com.heibaimiao.multilivetv.vod.VodService
import kotlinx.coroutines.launch

@Composable
fun HistoryScreen(
    history: WatchHistoryStore,
    vod: VodService,
    onPlay: (VodPlaybackRequest) -> Unit,
) {
    var items by remember { mutableStateOf(history.getAll()) }
    var loadingId by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current

    fun reload() {
        items = history.getAll()
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) reload()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    fun play(record: WatchHistoryRecord) {
        if (loadingId != null) return
        scope.launch {
            loadingId = record.videoId
            error = null
            try {
                onPlay(WatchHistoryResume.loadRequest(vod, record))
            } catch (e: Exception) {
                error = RequestFailure.userFacingMessage(e)
            } finally {
                loadingId = null
            }
        }
    }

    Column(Modifier.fillMaxSize().background(AppTheme.screenBackground)) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = AppTheme.screenPadding, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("历史播放", color = AppTheme.textPrimary, style = androidx.compose.material3.MaterialTheme.typography.titleLarge)
            if (items.isNotEmpty()) {
                TextButton(onClick = {
                    history.clear()
                    reload()
                    error = null
                }) { Text("清空历史") }
            }
        }
        error?.let {
            Text(it, color = AppTheme.textSecondary, modifier = Modifier.padding(horizontal = AppTheme.screenPadding, vertical = 8.dp))
        }
        when {
            items.isEmpty() -> Centered { Text("暂无播放历史", color = AppTheme.textTertiary) }
            else -> LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(AppTheme.screenPadding),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                items(items, key = { it.videoId }) { record ->
                    HistoryRow(
                        record = record,
                        loading = loadingId == record.videoId,
                        onPlay = { play(record) },
                        onDelete = {
                            history.delete(record.videoId)
                            reload()
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun HistoryRow(
    record: WatchHistoryRecord,
    loading: Boolean,
    onPlay: () -> Unit,
    onDelete: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onPlay),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(
            Modifier
                .width(96.dp)
                .aspectRatio(2f / 3f)
                .clip(RoundedCornerShape(AppTheme.posterRadius))
                .background(AppTheme.elevated),
        ) {
            AsyncImage(
                model = record.cover.ifEmpty { null },
                contentDescription = record.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
        Column(Modifier.weight(1f)) {
            Text(record.title.ifBlank { "未知影片" }, color = AppTheme.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (record.episodeTitle.isNotBlank()) {
                Text(record.episodeTitle, color = AppTheme.accent, modifier = Modifier.padding(top = 6.dp))
            }
            Text(
                WatchHistoryProgress.progressLabel(record),
                color = AppTheme.textSecondary,
                modifier = Modifier.padding(top = 6.dp),
            )
            Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onPlay, enabled = !loading) {
                    Text(if (loading) "正在恢复…" else "继续播放")
                }
                TextButton(onClick = onDelete, enabled = !loading) { Text("删除") }
            }
        }
    }
}
