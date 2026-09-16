package com.heibaimiao.multilivetv.player

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import androidx.tv.material3.Text
import com.heibaimiao.multilivetv.R
import com.heibaimiao.multilivetv.history.VodPlaybackRequest
import com.heibaimiao.multilivetv.history.WatchHistoryDisplay
import com.heibaimiao.multilivetv.history.WatchHistoryProgress
import com.heibaimiao.multilivetv.history.WatchHistoryRecorder
import com.heibaimiao.multilivetv.history.WatchHistoryStore
import com.heibaimiao.multilivetv.live.LiveChannel
import com.heibaimiao.multilivetv.live.LiveChannelNav
import com.heibaimiao.multilivetv.live.LiveGroup
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

data class LivePlaySession(
    val group: LiveGroup,
    val channel: LiveChannel,
)

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
            .setLoadControl(
                DefaultLoadControl.Builder()
                    .setBufferDurationsMs(
                        VodPlayerHud.MIN_BUFFER_MS,
                        VodPlayerHud.MAX_BUFFER_MS,
                        VodPlayerHud.PLAYBACK_BUFFER_MS,
                        VodPlayerHud.REBUFFER_MS,
                    )
                    .setPrioritizeTimeOverSizeThresholds(true)
                    .build(),
            )
            .setMediaSourceFactory(DefaultMediaSourceFactory(httpFactory))
            .build()
            .apply {
                if (!WatchHistoryDisplay.showPlayingOverlay) {
                    trackSelectionParameters = trackSelectionParameters
                        .buildUpon()
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                        .build()
                }
            }
    }

    fun capture(force: Boolean) {
        val current = requestState.value
        val candidate = current.candidates.getOrNull(indexState.value) ?: return
        captureWatchHistory(recorder, current, candidate, player, force)
    }

    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                val next = VodPlaybackFailover.nextIndex(index, candidates.size)
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

    PlayerStage(
        player = player,
        ready = ready,
        status = status,
        onClose = onClose,
        onSeekCommitted = { capture(true) },
    )
}

@Composable
fun LivePlayerScreen(
    session: LivePlaySession,
    onClose: () -> Unit,
) {
    val context = LocalContext.current
    var current by remember { mutableStateOf(session.channel) }
    var osd by remember { mutableStateOf(session.channel.name) }
    BackHandler(onBack = onClose)

    val player = remember {
        ExoPlayer.Builder(context).build()
    }
    DisposableEffect(player) {
        onDispose { player.release() }
    }

    LaunchedEffect(current.id) {
        osd = current.name
        val stream = current.streams.first()
        val headers = stream.headers.ifEmpty { mapOf("User-Agent" to NetworkConfig.USER_AGENT) }
        val httpFactory = OkHttpDataSource.Factory(HttpClient.okHttp)
            .setUserAgent(headers["User-Agent"] ?: NetworkConfig.USER_AGENT)
            .setDefaultRequestProperties(headers)
        player.setMediaSource(DefaultMediaSourceFactory(httpFactory).createMediaSource(MediaItem.fromUri(stream.url)))
        player.prepare()
        player.playWhenReady = true
        delay(2_400)
        if (osd == current.name) osd = ""
    }

    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(focus)
            .focusable()
            .onPreviewKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                val zap = when (event.key) {
                    Key.DirectionUp, Key.ChannelUp -> -1
                    Key.DirectionDown, Key.ChannelDown -> 1
                    else -> null
                }
                if (zap != null) {
                    LiveChannelNav.step(session.group, current, zap)?.let { current = it }
                    true
                } else {
                    false
                }
            },
    ) {
        PlayerSurface(player, fillScreen = true)
        if (WatchHistoryDisplay.showPlayingOverlay && osd.isNotEmpty()) {
            Text(
                osd,
                color = Color.White,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(32.dp)
                    .background(Color.Black.copy(alpha = 0.55f))
                    .padding(horizontal = 16.dp, vertical = 10.dp),
            )
        }
    }
}

@Composable
private fun PlayerStage(
    player: ExoPlayer,
    ready: Boolean,
    status: String,
    onClose: () -> Unit,
    onSeekCommitted: () -> Unit,
) {
    val focus = remember { FocusRequester() }
    var hudVisible by remember { mutableStateOf(true) }
    var isPlaying by remember { mutableStateOf(player.isPlaying) }
    var positionMs by remember { mutableLongStateOf(0L) }
    var durationMs by remember { mutableLongStateOf(0L) }
    var bufferedMs by remember { mutableLongStateOf(0L) }
    var holdDir by remember { mutableIntStateOf(0) }
    val seeking = holdDir != 0
    val seekingState = rememberUpdatedState(seeking)
    val onSeekCommittedState = rememberUpdatedState(onSeekCommitted)

    fun applySeek(deltaMs: Long) {
        val duration = player.duration.let { if (it > 0L) it else 0L }
        val target = VodPlayerHud.seekBy(player.currentPosition, duration, deltaMs)
        player.seekTo(target)
        positionMs = target
        durationMs = duration
        hudVisible = true
        onSeekCommittedState.value()
    }

    fun togglePlay() {
        if (player.isPlaying) player.pause() else player.play()
        hudVisible = true
    }

    BackHandler {
        when (VodPlayerHud.onBack(hudVisible && ready)) {
            VodPlayerHud.BackAction.Hide -> hudVisible = false
            VodPlayerHud.BackAction.Exit -> onClose()
        }
    }

    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }

    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    LaunchedEffect(ready) {
        if (ready) hudVisible = true
    }

    LaunchedEffect(player, ready) {
        if (!ready) return@LaunchedEffect
        while (true) {
            if (!seekingState.value) {
                positionMs = player.currentPosition.coerceAtLeast(0L)
                val duration = player.duration
                durationMs = if (duration > 0L) duration else 0L
                val buffered = player.bufferedPosition
                bufferedMs = if (buffered > 0L) buffered else 0L
            }
            delay(250)
        }
    }

    LaunchedEffect(hudVisible, isPlaying, seeking, ready) {
        if (!ready || !VodPlayerHud.shouldAutoHide(hudVisible, isPlaying, seeking)) return@LaunchedEffect
        delay(VodPlayerHud.AUTO_HIDE_MS)
        hudVisible = false
    }

    LaunchedEffect(holdDir) {
        if (holdDir == 0) return@LaunchedEffect
        var elapsed = 0L
        while (true) {
            val interval = VodPlayerHud.holdIntervalMs(elapsed)
            delay(interval)
            elapsed += interval
            applySeek(holdDir * VodPlayerHud.holdStepMs(elapsed))
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(focus)
            .focusable()
            .onPreviewKeyEvent { event ->
                if (!ready) return@onPreviewKeyEvent false
                val key = event.key
                val isLeft = key == Key.DirectionLeft || key == Key.MediaRewind
                val isRight = key == Key.DirectionRight || key == Key.MediaFastForward
                if (event.type == KeyEventType.KeyUp) {
                    if (isLeft && holdDir == -1) holdDir = 0
                    if (isRight && holdDir == 1) holdDir = 0
                    return@onPreviewKeyEvent isLeft || isRight
                }
                if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                when {
                    isLeft -> {
                        if (holdDir != -1) {
                            applySeek(-VodPlayerHud.STEP_MS)
                            holdDir = -1
                        }
                        true
                    }
                    isRight -> {
                        if (holdDir != 1) {
                            applySeek(VodPlayerHud.STEP_MS)
                            holdDir = 1
                        }
                        true
                    }
                    key == Key.DirectionUp || key == Key.DirectionDown -> {
                        hudVisible = true
                        true
                    }
                    key == Key.DirectionCenter ||
                        key == Key.Enter ||
                        key == Key.MediaPlayPause ||
                        key == Key.MediaPlay ||
                        key == Key.MediaPause -> {
                        togglePlay()
                        true
                    }
                    else -> false
                }
            },
    ) {
        if (ready) {
            PlayerSurface(player)
            TvVodHud(
                visible = hudVisible,
                playing = isPlaying,
                positionMs = positionMs,
                durationMs = durationMs,
                bufferedMs = bufferedMs,
                modifier = Modifier.fillMaxSize(),
            )
            if (WatchHistoryDisplay.showPlayingOverlay && status.isNotEmpty()) {
                Text(
                    status,
                    color = Color.White,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(32.dp),
                )
            }
        } else {
            Text(status, color = AppTheme.textSecondary, modifier = Modifier.align(Alignment.Center))
        }
    }
}

@Composable
private fun PlayerSurface(player: ExoPlayer, fillScreen: Boolean = false) {
    val resizeMode = if (fillScreen) {
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM
    } else {
        AspectRatioFrameLayout.RESIZE_MODE_FIT
    }
    AndroidView(
        factory = { ctx ->
            (LayoutInflater.from(ctx).inflate(R.layout.player_surface, null) as PlayerView).apply {
                this.player = player
                keepScreenOn = true
                useController = false
                this.resizeMode = resizeMode
                if (!WatchHistoryDisplay.showPlayingOverlay) {
                    subtitleView?.visibility = android.view.View.GONE
                }
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                )
            }
        },
        modifier = Modifier.fillMaxSize(),
        update = { view ->
            view.player = player
            view.resizeMode = resizeMode
        },
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
