package com.heibaimiao.multilivetv.ui

import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.tv.material3.Button
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
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
    val firstFocus = remember { FocusRequester() }

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

    Column(Modifier.fillMaxSize().background(AppTheme.screenBackground).padding(AppTheme.screenPadding)) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("历史播放", color = AppTheme.textPrimary)
            if (items.isNotEmpty()) {
                Button(onClick = {
                    history.clear()
                    reload()
                    error = null
                }) { Text("清空历史") }
            }
        }
        error?.let { StatusText(it) }
        when {
            items.isEmpty() -> Centered { StatusText("暂无播放历史") }
            else -> Column(Modifier.fillMaxSize().padding(top = 16.dp)) {
                LaunchedEffect(items.firstOrNull()?.videoId) {
                    runCatching { firstFocus.requestFocus() }
                }
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    itemsIndexed(items, key = { _, item -> item.videoId }) { index, record ->
                        HistoryRow(
                            record = record,
                            loading = loadingId == record.videoId,
                            firstFocus = if (index == 0) firstFocus else null,
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
}

@Composable
private fun HistoryRow(
    record: WatchHistoryRecord,
    loading: Boolean,
    firstFocus: FocusRequester?,
    onPlay: () -> Unit,
    onDelete: () -> Unit,
) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Surface(
            onClick = onPlay,
            colors = ClickableSurfaceDefaults.colors(
                containerColor = AppTheme.elevated,
                contentColor = AppTheme.textPrimary,
                focusedContainerColor = AppTheme.accent,
                focusedContentColor = androidx.compose.ui.graphics.Color.Black,
            ),
            modifier = Modifier
                .weight(1f)
                .then(if (firstFocus != null) Modifier.focusRequester(firstFocus) else Modifier),
        ) {
            Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Box(
                    Modifier
                        .width(96.dp)
                        .aspectRatio(2f / 3f)
                        .background(AppTheme.screenBackground),
                ) {
                    AsyncImage(
                        model = record.cover.ifEmpty { null },
                        contentDescription = record.title,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                Column(Modifier.weight(1f)) {
                    Text(record.title.ifBlank { "未知影片" }, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (record.episodeTitle.isNotBlank()) {
                        Text(record.episodeTitle, modifier = Modifier.padding(top = 8.dp))
                    }
                    Text(
                        WatchHistoryProgress.progressLabel(record),
                        color = AppTheme.textSecondary,
                        modifier = Modifier.padding(top = 8.dp),
                    )
                    Text(if (loading) "正在恢复播放…" else "继续播放", modifier = Modifier.padding(top = 10.dp))
                }
            }
        }
        Button(onClick = onDelete) { Text("删除") }
    }
}
