package com.heibaimiao.multilivetv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.heibaimiao.multilivetv.history.VodPlaybackRequest
import com.heibaimiao.multilivetv.history.WatchHistoryProgress
import com.heibaimiao.multilivetv.history.WatchHistoryRecord
import com.heibaimiao.multilivetv.history.WatchHistoryResume
import com.heibaimiao.multilivetv.history.WatchHistoryStore
import com.heibaimiao.multilivetv.model.DetailResponse
import com.heibaimiao.multilivetv.model.Episode
import com.heibaimiao.multilivetv.model.VodItem
import com.heibaimiao.multilivetv.net.RequestFailure
import com.heibaimiao.multilivetv.parser.PlayLineWeighting
import com.heibaimiao.multilivetv.vod.VodService
import kotlinx.coroutines.launch

@Composable
fun DetailScreen(
    item: VodItem,
    vod: VodService,
    history: WatchHistoryStore,
    onPlay: (VodPlaybackRequest) -> Unit,
    onBack: () -> Unit,
) {
    var detail by remember { mutableStateOf<DetailResponse?>(null) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var selectedSourceIndex by remember { mutableIntStateOf(0) }
    var continueRecord by remember { mutableStateOf<WatchHistoryRecord?>(null) }
    val scope = rememberCoroutineScope()

    fun load() {
        scope.launch {
            loading = true
            error = null
            try {
                detail = vod.detail(item.resolvedSourceId, item.vodId, item.variants.orEmpty()) { primary ->
                    val ranked = PlayLineWeighting.forDetailDisplay(primary.playSources)
                    detail = primary.copy(playSources = ranked)
                    selectedSourceIndex = PlayLineWeighting.preferredPlayableIndex(ranked)
                    loading = false
                }
                detail = detail?.let { it.copy(playSources = PlayLineWeighting.forDetailDisplay(it.playSources)) }
                selectedSourceIndex = PlayLineWeighting.preferredPlayableIndex(detail?.playSources.orEmpty())
            } catch (e: Exception) {
                error = RequestFailure.userFacingMessage(e)
            } finally {
                loading = false
            }
        }
    }

    LaunchedEffect(item.id) { load() }
    LaunchedEffect(detail?.vod?.id) {
        val loaded = detail ?: return@LaunchedEffect
        val record = WatchHistoryResume.lookup(history, loaded.vod) ?: WatchHistoryResume.lookup(history, item)
        continueRecord = record?.takeIf { WatchHistoryResume.resumePositionMs(it) > 0L }
    }

    val playFromHistory: (Boolean) -> Unit = { restart ->
        val loaded = detail
        val record = continueRecord
        if (loaded != null && record != null) {
            WatchHistoryResume.playbackRequest(loaded, record, restart = restart)?.let(onPlay)
            continueRecord = null
        }
    }

    when {
        detail != null -> DetailBody(
            detail = detail!!,
            selectedSourceIndex = selectedSourceIndex,
            history = history,
            onSelectSource = { selectedSourceIndex = it },
            onPlay = onPlay,
            onBack = onBack,
        )
        loading -> Centered { CircularProgressIndicator(color = AppTheme.accent) }
        else -> Centered {
            Column {
                Text(error ?: "加载失败", color = AppTheme.textSecondary)
                Button(onClick = { load() }, modifier = Modifier.padding(top = 12.dp)) { Text("重试") }
            }
        }
    }

    val prompt = continueRecord
    if (prompt != null && detail != null) {
        val clock = WatchHistoryProgress.formatClock(WatchHistoryResume.resumePositionMs(prompt))
        AlertDialog(
            onDismissRequest = { continueRecord = null },
            title = { Text("是否继续播放？") },
            text = { Text("上次看到 ${prompt.episodeTitle.ifBlank { prompt.title }} $clock") },
            confirmButton = {
                TextButton(onClick = { playFromHistory(false) }) { Text("继续播放 $clock") }
            },
            dismissButton = {
                TextButton(onClick = { playFromHistory(true) }) { Text("重新开始") }
            },
        )
    }
}

@Composable
private fun DetailBody(
    detail: DetailResponse,
    selectedSourceIndex: Int,
    history: WatchHistoryStore,
    onSelectSource: (Int) -> Unit,
    onPlay: (VodPlaybackRequest) -> Unit,
    onBack: () -> Unit,
) {
    val vod = detail.vod
    val sources = detail.playSources
    val selected = sources.getOrNull(selectedSourceIndex)
    fun playEpisode(episode: Episode) {
        val record = WatchHistoryResume.lookup(history, vod)
        val sameEpisode = record != null && (
            record.episodeId == episode.url ||
                (record.episodeTitle.isNotBlank() && record.episodeTitle == episode.name)
            )
        val resume = if (sameEpisode) WatchHistoryResume.resumePositionMs(record) else 0L
        onPlay(WatchHistoryResume.playbackRequest(detail, selectedSourceIndex, episode, resume))
    }
    Column(
        Modifier
            .fillMaxSize()
            .background(AppTheme.screenBackground)
            .verticalScroll(rememberScrollState())
            .padding(AppTheme.screenPadding),
    ) {
        Text("返回", color = AppTheme.accent, modifier = Modifier.clickable(onClick = onBack).padding(bottom = 12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
            AsyncImage(
                model = vod.vodPic,
                contentDescription = vod.vodName,
                contentScale = ContentScale.Crop,
                modifier = Modifier.width(180.dp).aspectRatio(2f / 3f).clip(RoundedCornerShape(AppTheme.posterRadius)),
            )
            Column(Modifier.weight(1f)) {
                Text(vod.vodName, color = AppTheme.textPrimary, style = androidx.compose.material3.MaterialTheme.typography.headlineSmall)
                vod.displayGenreLine?.let { Text(it, color = AppTheme.textSecondary, modifier = Modifier.padding(top = 8.dp)) }
                vod.displayRemarks?.let { Text(it, color = AppTheme.accent, modifier = Modifier.padding(top = 6.dp)) }
                vod.displayBlurb?.let {
                    Text(it, color = AppTheme.textSecondary, modifier = Modifier.padding(top = 12.dp), maxLines = 8)
                }
            }
        }
        Spacer(Modifier.height(20.dp))
        if (sources.isEmpty()) {
            Text("暂无播放线路", color = AppTheme.textSecondary)
        } else {
            Text("线路", color = AppTheme.textTertiary)
            Spacer(Modifier.height(8.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                sources.forEachIndexed { index, source ->
                    FilterChip(
                        selected = index == selectedSourceIndex,
                        onClick = { onSelectSource(index) },
                        label = { Text(source.name) },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = AppTheme.accent,
                            selectedLabelColor = androidx.compose.ui.graphics.Color.Black,
                            containerColor = AppTheme.elevated,
                            labelColor = AppTheme.textSecondary,
                        ),
                    )
                }
            }
            Spacer(Modifier.height(16.dp))
            Text("选集", color = AppTheme.textTertiary)
            Spacer(Modifier.height(8.dp))
            EpisodeGrid(selected?.episodes.orEmpty()) { episode ->
                playEpisode(episode)
            }
        }
    }
}

@Composable
private fun EpisodeGrid(episodes: List<Episode>, onPlay: (Episode) -> Unit) {
    LazyVerticalGrid(
        columns = GridCells.Adaptive(112.dp),
        modifier = Modifier.height(((episodes.size / 6 + 1) * 56).coerceAtMost(420).dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        userScrollEnabled = true,
    ) {
        items(episodes, key = { it.url + it.name }) { episode ->
            FilterChip(
                selected = false,
                onClick = { onPlay(episode) },
                label = { Text(episode.name, maxLines = 1) },
                colors = FilterChipDefaults.filterChipColors(
                    containerColor = AppTheme.elevated,
                    labelColor = AppTheme.textPrimary,
                ),
            )
        }
    }
}
