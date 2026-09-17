package com.heibaimiao.multilivetv.player

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import com.heibaimiao.multilivetv.R
import com.heibaimiao.multilivetv.history.VodPlaybackRequest
import com.heibaimiao.multilivetv.history.WatchHistoryProgress
import com.heibaimiao.multilivetv.history.WatchHistoryRecorder
import com.heibaimiao.multilivetv.history.WatchHistoryStore
import com.heibaimiao.multilivetv.live.VodMediaProbe
import com.heibaimiao.multilivetv.net.HttpClient
import com.heibaimiao.multilivetv.net.NetworkConfig
import com.heibaimiao.multilivetv.parser.PlaybackCandidate
import com.heibaimiao.multilivetv.parser.PlaybackSupport
import com.heibaimiao.multilivetv.parser.VodPlaybackFailover
import com.heibaimiao.multilivetv.ui.AppTheme
import com.heibaimiao.multilivetv.vod.VodService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

@Composable
fun PlayerScreen(
    request: VodPlaybackRequest,
    vod: VodService,
    history: WatchHistoryStore,
    onClose: () -> Unit,
) {
    val context = LocalContext.current
    val candidates = request.candidates
    var index by remember { mutableIntStateOf(0) }
    var status by remember { mutableStateOf("正在解析播放地址…") }
    var ready by remember { mutableStateOf(false) }
    var mediaUrl by remember { mutableStateOf<String?>(null) }
    var headers by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    val recorder = remember(history) { WatchHistoryRecorder(history) }
    val requestState = rememberUpdatedState(request)
    val indexState = rememberUpdatedState(index)

    val player = remember {
        val httpFactory = OkHttpDataSource.Factory(HttpClient.okHttp)
            .setUserAgent(NetworkConfig.USER_AGENT)
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(httpFactory))
            .build()
    }

    fun capture(force: Boolean) {
        val current = requestState.value
        val candidate = current.candidates.getOrNull(indexState.value) ?: return
        captureWatchHistory(recorder, current, candidate, player, force)
    }

    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                val next = VodPlaybackFailover.nextIndex(indexState.value, candidates.size)
                if (next != null) {
                    index = next
                } else {
                    status = PlaybackSupport.userFacingError(mediaUrl.orEmpty(), error.message)
                    ready = false
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (!isPlaying) capture(true)
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_ENDED) capture(true)
            }
        }
        player.addListener(listener)
        onDispose {
            capture(true)
            player.removeListener(listener)
            player.release()
        }
    }

    LaunchedEffect(player, ready) {
        if (!ready) return@LaunchedEffect
        while (true) {
            capture(false)
            delay(1_000)
        }
    }

    LaunchedEffect(index, candidates) {
        ready = false
        mediaUrl = null
        val candidate = candidates.getOrNull(index)
        if (candidate == null) {
            status = "没有可播放的线路"
            return@LaunchedEffect
        }
        status = if (candidates.size > 1) {
            "正在解析播放地址…（线路 ${index + 1}/${candidates.size}）"
        } else {
            "正在解析播放地址…"
        }
        val source = vod.source(candidate.sourceId)
        val parsed = runCatching { vod.parsePlay(candidate.sourceId, candidate.episode.url) }.getOrNull()
        val url = parsed?.url ?: candidate.episode.url
        if (!PlaybackSupport.isDirectMediaURL(url)) {
            val next = VodPlaybackFailover.nextIndex(index, candidates.size)
            if (next != null) {
                index = next
                return@LaunchedEffect
            }
            status = PlaybackSupport.userFacingError(url, null)
            return@LaunchedEffect
        }
        val playHeaders = source?.let { PlaybackSupport.httpHeaders(it, url) } ?: mapOf("User-Agent" to NetworkConfig.USER_AGENT)
        val playable = withContext(Dispatchers.IO) { VodMediaProbe.isLikelyPlayable(url, playHeaders) }
        if (!playable) {
            val next = VodPlaybackFailover.nextIndex(index, candidates.size)
            if (next != null) {
                index = next
                return@LaunchedEffect
            }
            status = "播放失败，请换线路重试"
            return@LaunchedEffect
        }
        headers = playHeaders
        mediaUrl = url
        status = candidate.episode.name
        ready = true
    }

    LaunchedEffect(mediaUrl, headers) {
        val url = mediaUrl ?: return@LaunchedEffect
        val httpFactory = OkHttpDataSource.Factory(HttpClient.okHttp)
            .setUserAgent(headers["User-Agent"] ?: NetworkConfig.USER_AGENT)
            .setDefaultRequestProperties(headers)
        player.setMediaSource(
            DefaultMediaSourceFactory(httpFactory).createMediaSource(MediaItem.fromUri(url)),
        )
        player.prepare()
        val resumeAt = request.resumePositionMs
        if (resumeAt > 0L) player.seekTo(resumeAt)
        player.playWhenReady = true
        capture(true)
    }

    val candidate = candidates.getOrNull(index)
    val title = candidate?.episode?.name?.ifBlank { status } ?: status
    val subtitle = when {
        !ready -> null
        candidates.size > 1 -> "线路 ${index + 1}/${candidates.size}"
        else -> null
    }

    PlayerChrome(
        player = player,
        ready = ready,
        status = status,
        title = title,
        subtitle = subtitle,
        isLive = false,
        onClose = onClose,
    )
}

@Composable
fun LivePlayerScreen(url: String, headers: Map<String, String>, title: String, onClose: () -> Unit) {
    val context = LocalContext.current
    var failed by remember { mutableStateOf<String?>(null) }
    val player = remember {
        ExoPlayer.Builder(context).build()
    }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                failed = PlaybackSupport.userFacingError(url, error.message)
            }
        }
        player.addListener(listener)
        val httpFactory = OkHttpDataSource.Factory(HttpClient.okHttp)
            .setUserAgent(headers["User-Agent"] ?: NetworkConfig.USER_AGENT)
            .setDefaultRequestProperties(headers.ifEmpty { mapOf("User-Agent" to NetworkConfig.USER_AGENT) })
        player.setMediaSource(DefaultMediaSourceFactory(httpFactory).createMediaSource(MediaItem.fromUri(url)))
        player.prepare()
        player.playWhenReady = true
        onDispose {
            player.removeListener(listener)
            player.release()
        }
    }
    if (failed != null) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            Column(
                Modifier.align(Alignment.Center),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(failed!!, color = AppTheme.textSecondary, modifier = Modifier.padding(16.dp))
            }
            IconButton(
                onClick = onClose,
                modifier = Modifier
                    .statusBarsPadding()
                    .padding(4.dp),
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "关闭",
                    tint = Color.White,
                )
            }
        }
    } else {
        PlayerChrome(
            player = player,
            ready = true,
            status = title,
            title = title.ifBlank { "直播" },
            subtitle = null,
            isLive = true,
            onClose = onClose,
        )
    }
}

@Composable
private fun PlayerChrome(
    player: ExoPlayer,
    ready: Boolean,
    status: String,
    title: String,
    subtitle: String?,
    isLive: Boolean,
    onClose: () -> Unit,
) {
    var playerView by remember { mutableStateOf<PlayerView?>(null) }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (ready) {
            PlayerSurface(player) { playerView = it }
            CinemaPlayerOverlay(
                player = player,
                title = title,
                subtitle = subtitle,
                isLive = isLive,
                playerView = playerView,
                onClose = onClose,
            )
        } else {
            Column(
                Modifier.align(Alignment.Center),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                CircularProgressIndicator(color = AppTheme.accent)
                Text(status, color = AppTheme.textSecondary, modifier = Modifier.padding(16.dp))
            }
            IconButton(
                onClick = onClose,
                modifier = Modifier
                    .statusBarsPadding()
                    .padding(4.dp),
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "关闭",
                    tint = Color.White,
                )
            }
        }
    }
}

@Composable
private fun PlayerSurface(player: ExoPlayer, onView: (PlayerView) -> Unit) {
    AndroidView(
        factory = { ctx ->
            (LayoutInflater.from(ctx).inflate(R.layout.player_surface, null) as PlayerView).apply {
                this.player = player
                keepScreenOn = true
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                )
                onView(this)
            }
        },
        modifier = Modifier.fillMaxSize(),
        update = { it.player = player },
    )
}

private fun captureWatchHistory(
    recorder: WatchHistoryRecorder,
    request: VodPlaybackRequest,
    candidate: PlaybackCandidate,
    player: ExoPlayer,
    force: Boolean,
) {
    val duration = player.duration
    recorder.save(
        WatchHistoryProgress.fromPlayback(
            item = request.item,
            episode = candidate.episode,
            episodeIndex = request.episodeIndex,
            sourceId = candidate.sourceId,
            sourceName = request.sourceName,
            positionMs = player.currentPosition,
            durationMs = if (duration > 0L) duration else 0L,
            now = System.currentTimeMillis(),
        ),
        force = force,
    )
}
