package com.heibaimiao.multilivetv.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Button
import androidx.tv.material3.ButtonDefaults
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import coil.compose.AsyncImage
import com.heibaimiao.multilivetv.history.VodPlaybackRequest
import com.heibaimiao.multilivetv.history.WatchHistoryDisplay
import com.heibaimiao.multilivetv.history.WatchHistoryProgress
import com.heibaimiao.multilivetv.history.WatchHistoryRecord
import com.heibaimiao.multilivetv.history.WatchHistoryResume
import com.heibaimiao.multilivetv.history.WatchHistoryStore
import com.heibaimiao.multilivetv.model.DetailResponse
import com.heibaimiao.multilivetv.model.Episode
import com.heibaimiao.multilivetv.model.VodItem
import com.heibaimiao.multilivetv.net.RequestFailure
import com.heibaimiao.multilivetv.parser.EpisodePaging
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
    BackHandler(onBack = {
        if (continueRecord != null) continueRecord = null else onBack()
    })

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

    Box(Modifier.fillMaxSize()) {
        when {
            detail != null -> DetailBody(
                detail = detail!!,
                selectedSourceIndex = selectedSourceIndex,
                history = history,
                onSelectSource = { selectedSourceIndex = it },
                onPlay = onPlay,
                onBack = onBack,
            )
            loading -> Centered { StatusText("加载详情…") }
            else -> Centered {
                Column {
                    StatusText(error ?: "加载失败")
                    TvAction("重试") { load() }
                }
            }
        }
        val prompt = continueRecord
        if (prompt != null && detail != null) {
            ContinuePlaybackDialog(
                record = prompt,
                onContinue = { playFromHistory(false) },
                onRestart = { playFromHistory(true) },
            )
        }
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
    val playFocus = remember { FocusRequester() }
    val episodes = selected?.episodes.orEmpty()
    fun playEpisode(episode: Episode) {
        val record = WatchHistoryResume.lookup(history, vod)
        val sameEpisode = record != null && (
            record.episodeId == episode.url ||
                (record.episodeTitle.isNotBlank() && record.episodeTitle == episode.name)
            )
        val resume = if (sameEpisode) WatchHistoryResume.resumePositionMs(record) else 0L
        onPlay(WatchHistoryResume.playbackRequest(detail, selectedSourceIndex, episode, resume))
    }
    LaunchedEffect(episodes.firstOrNull()?.url) {
        if (episodes.isNotEmpty()) runCatching { playFocus.requestFocus() }
    }
    Column(
        Modifier
            .fillMaxSize()
            .background(AppTheme.screenBackground)
            .padding(AppTheme.screenPadding),
    ) {
        Button(onClick = onBack) { Text("返回") }
        Spacer(Modifier.height(16.dp))
        Row(
            Modifier.weight(1f).fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            AsyncImage(
                model = vod.vodPic,
                contentDescription = vod.vodName,
                contentScale = ContentScale.Crop,
                modifier = Modifier.width(160.dp).aspectRatio(2f / 3f),
            )
            Column(Modifier.weight(1f).fillMaxHeight()) {
                Text(vod.vodName, color = AppTheme.textPrimary)
                vod.displayGenreLine?.let { Text(it, color = AppTheme.textSecondary, modifier = Modifier.padding(top = 8.dp)) }
                vod.displayBlurb?.let {
                    Text(it, color = AppTheme.textSecondary, modifier = Modifier.padding(top = 12.dp), maxLines = 3)
                }
                if (sources.isEmpty()) {
                    Spacer(Modifier.height(16.dp))
                    StatusText("暂无播放线路")
                } else {
                    Spacer(Modifier.height(16.dp))
                    Text("线路", color = AppTheme.textTertiary)
                    Spacer(Modifier.height(8.dp))
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        itemsIndexed(sources, key = { _, source -> source.key + source.name }) { index, source ->
                            Surface(
                                onClick = { onSelectSource(index) },
                                colors = ClickableSurfaceDefaults.colors(
                                    containerColor = if (index == selectedSourceIndex) AppTheme.accent else AppTheme.elevated,
                                    contentColor = if (index == selectedSourceIndex) androidx.compose.ui.graphics.Color.Black else AppTheme.textSecondary,
                                    focusedContainerColor = AppTheme.accent,
                                    focusedContentColor = androidx.compose.ui.graphics.Color.Black,
                                ),
                            ) {
                                Text(source.name, modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp))
                            }
                        }
                    }
                    Spacer(Modifier.height(16.dp))
                    Text("选集 · 共${episodes.size}集", color = AppTheme.textTertiary)
                    Spacer(Modifier.height(8.dp))
                    if (episodes.isEmpty()) {
                        StatusText("暂无选集")
                    } else {
                        var pageIndex by remember(selectedSourceIndex, episodes.size) { mutableIntStateOf(0) }
                        val pages = remember(episodes.size) { EpisodePaging.pages(episodes.size) }
                        val page = pages.getOrElse(pageIndex.coerceIn(0, pages.lastIndex)) { pages.first() }
                        val visible = remember(episodes, page) { EpisodePaging.slice(episodes, page) }
                        if (pages.size > 1) {
                            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                itemsIndexed(pages, key = { _, item -> item.label }) { index, item ->
                                    Surface(
                                        onClick = { pageIndex = index },
                                        colors = ClickableSurfaceDefaults.colors(
                                            containerColor = if (index == pageIndex) AppTheme.accent else AppTheme.elevated,
                                            contentColor = if (index == pageIndex) androidx.compose.ui.graphics.Color.Black else AppTheme.textSecondary,
                                            focusedContainerColor = AppTheme.accent,
                                            focusedContentColor = androidx.compose.ui.graphics.Color.Black,
                                        ),
                                    ) {
                                        Text(item.label, modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp))
                                    }
                                }
                            }
                            Spacer(Modifier.height(10.dp))
                        }
                        EpisodeGrid(
                            episodes = visible,
                            firstFocus = playFocus,
                            modifier = Modifier.weight(1f).fillMaxWidth(),
                        ) { episode ->
                            playEpisode(episode)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EpisodeGrid(
    episodes: List<Episode>,
    firstFocus: FocusRequester,
    modifier: Modifier = Modifier,
    onPlay: (Episode) -> Unit,
) {
    LazyVerticalGrid(
        columns = GridCells.Adaptive(88.dp),
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        itemsIndexed(episodes, key = { _, episode -> episode.url + episode.name }) { index, episode ->
            Surface(
                onClick = { onPlay(episode) },
                colors = ClickableSurfaceDefaults.colors(
                    containerColor = AppTheme.elevated,
                    contentColor = AppTheme.textPrimary,
                    focusedContainerColor = AppTheme.accent,
                    focusedContentColor = androidx.compose.ui.graphics.Color.Black,
                ),
                modifier = Modifier.then(if (index == 0) Modifier.focusRequester(firstFocus) else Modifier),
            ) {
                Box(
                    Modifier.fillMaxWidth().height(44.dp).padding(horizontal = 4.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        episode.name.ifBlank { "播放" },
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
}

@Composable
private fun ContinuePlaybackDialog(
    record: WatchHistoryRecord,
    onContinue: () -> Unit,
    onRestart: () -> Unit,
) {
    val focus = remember { FocusRequester() }
    val clock = WatchHistoryProgress.formatClock(WatchHistoryResume.resumePositionMs(record))
    val episode = WatchHistoryDisplay.episodeLine(record.title, record.episodeTitle)
    val cardShape = RoundedCornerShape(16.dp)
    LaunchedEffect(record.videoId) { runCatching { focus.requestFocus() } }
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.72f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier
                .width(420.dp)
                .clip(cardShape)
                .background(AppTheme.groupedBackground)
                .padding(horizontal = 28.dp, vertical = 28.dp),
        ) {
            Text(WatchHistoryDisplay.heading(), color = AppTheme.textPrimary)
            Text(
                record.title.ifBlank { "上次播放" },
                color = AppTheme.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 10.dp),
            )
            if (episode != null) {
                Text(
                    episode,
                    color = AppTheme.textTertiary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
            if (WatchHistoryDisplay.showProgressBar(record.durationMs)) {
                Row(
                    Modifier.padding(top = 16.dp, bottom = 24.dp).fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        Modifier
                            .weight(1f)
                            .height(4.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(Color.White.copy(alpha = 0.16f)),
                    ) {
                        Box(
                            Modifier
                                .fillMaxHeight()
                                .fillMaxWidth(record.progress.toFloat().coerceIn(0f, 1f))
                                .background(AppTheme.accent),
                        )
                    }
                    Text(
                        clock,
                        color = AppTheme.textSecondary,
                        modifier = Modifier.padding(start = 12.dp),
                    )
                }
            } else {
                Text(
                    clock,
                    color = AppTheme.textSecondary,
                    modifier = Modifier.padding(top = 16.dp, bottom = 24.dp),
                )
            }
            Button(
                onClick = onContinue,
                modifier = Modifier.fillMaxWidth().focusRequester(focus),
                colors = ButtonDefaults.colors(
                    containerColor = AppTheme.accent,
                    contentColor = Color.Black,
                    focusedContainerColor = Color.White,
                    focusedContentColor = Color.Black,
                ),
            ) {
                Text(WatchHistoryDisplay.continueAction(clock))
            }
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = onRestart,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.colors(
                    containerColor = AppTheme.elevated,
                    contentColor = AppTheme.textPrimary,
                    focusedContainerColor = AppTheme.accent,
                    focusedContentColor = Color.Black,
                ),
            ) {
                Text(WatchHistoryDisplay.restartAction())
            }
        }
    }
}
