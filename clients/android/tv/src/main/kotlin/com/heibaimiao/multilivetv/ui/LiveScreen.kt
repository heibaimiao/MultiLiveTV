package com.heibaimiao.multilivetv.ui

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import androidx.tv.material3.Border
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.ClickableSurfaceScale
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import com.heibaimiao.multilivetv.R
import com.heibaimiao.multilivetv.live.LiveCatalog
import com.heibaimiao.multilivetv.live.LiveChannel
import com.heibaimiao.multilivetv.live.LiveChannelMemory
import com.heibaimiao.multilivetv.live.LiveGroup
import com.heibaimiao.multilivetv.live.LiveOsdPolicy
import com.heibaimiao.multilivetv.live.LivePlayerPhase
import com.heibaimiao.multilivetv.live.LivePlayerPresentation
import com.heibaimiao.multilivetv.live.LivePreviewPhase
import com.heibaimiao.multilivetv.live.LivePreviewPolicy
import com.heibaimiao.multilivetv.live.LiveResume
import com.heibaimiao.multilivetv.live.LiveSelectionSync
import com.heibaimiao.multilivetv.live.LiveService
import com.heibaimiao.multilivetv.live.LiveSessionController
import com.heibaimiao.multilivetv.live.LiveUiMode
import com.heibaimiao.multilivetv.net.HttpClient
import com.heibaimiao.multilivetv.net.NetworkConfig
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Browse dim layer so list columns do not slice the video into “multi-window” stripes. */
private val BrowseDim = Color.Black.copy(alpha = 0.55f)
private val PanelScrim = Color.Black.copy(alpha = 0.78f)

private enum class LiveFocusColumn { GROUP, CHANNEL }

@Composable
fun LiveScreen(
    service: LiveService,
    memory: LiveChannelMemory,
    sidebarLiveFocus: FocusRequester,
    onWatchModeChanged: (Boolean) -> Unit = {},
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val controller = remember { LiveSessionController() }
    var liveState by remember { mutableStateOf(controller.state) }
    var groups by remember { mutableStateOf<List<LiveGroup>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    /** Committed group that owns the channel list (Selected ≠ mere Focus). */
    var selectedGroupName by remember { mutableStateOf<String?>(null) }
    var didInitialFocus by remember { mutableStateOf(false) }
    var osd by remember { mutableStateOf("") }
    var previewJob by remember { mutableStateOf<Job?>(null) }
    var focusColumn by remember { mutableStateOf(LiveFocusColumn.CHANNEL) }

    val groupFocus = remember { FocusRequester() }
    val channelFocusById = remember { mutableMapOf<String, FocusRequester>() }
    val watchFocus = remember { FocusRequester() }
    val channelListState = rememberLazyListState()
    val groupListState = rememberLazyListState()
    val itemShape = RoundedCornerShape(8.dp)

    fun sync() {
        liveState = controller.state
        onWatchModeChanged(controller.state.uiMode == LiveUiMode.WATCH)
    }

    fun requesterFor(channelId: String): FocusRequester =
        channelFocusById.getOrPut(channelId) { FocusRequester() }

    fun syncSelectedGroupToChannel(channelId: String?) {
        val name = LiveSelectionSync.groupNameForChannel(
            LiveCatalog.visibleGroups(groups),
            channelId,
        )
        if (name != null && selectedGroupName != name) {
            selectedGroupName = name
        }
    }

    val player = remember {
        ExoPlayer.Builder(context).build().apply {
            volume = 1f
            playWhenReady = true
            if (!LivePlayerPresentation.showTextTracks) {
                trackSelectionParameters = trackSelectionParameters
                    .buildUpon()
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                    .build()
            }
        }
    }

    DisposableEffect(player) {
        onDispose {
            player.stop()
            player.clearMediaItems()
            player.release()
        }
    }

    fun playStream(channel: LiveChannel, streamIndex: Int, modeGeneration: Int = controller.state.modeGeneration) {
        if (modeGeneration != controller.state.modeGeneration) return
        if (controller.alreadyShowing(channel.id, streamIndex)) {
            player.volume = controller.state.volume
            syncSelectedGroupToChannel(channel.id)
            return
        }
        val stream = channel.streams.getOrNull(streamIndex) ?: run {
            controller.onPlayerError("无法播放")
            sync()
            return
        }
        // Keep Selected group aligned with the channel we are switching to.
        if (selectedGroupName != channel.group) {
            selectedGroupName = channel.group
        }
        controller.beginSwitch(channel, streamIndex)
        player.volume = controller.state.volume
        sync()
        osd = LiveOsdPolicy.switchLabel(channel.name)
        player.stop()
        player.clearMediaItems()
        val headers = stream.headers.ifEmpty { mapOf("User-Agent" to NetworkConfig.USER_AGENT) }
        val httpFactory = OkHttpDataSource.Factory(HttpClient.okHttp)
            .setUserAgent(headers["User-Agent"] ?: NetworkConfig.USER_AGENT)
            .setDefaultRequestProperties(headers)
        if (modeGeneration != controller.state.modeGeneration) return
        player.setMediaSource(
            DefaultMediaSourceFactory(httpFactory).createMediaSource(MediaItem.fromUri(stream.url)),
        )
        player.prepare()
        player.playWhenReady = true
        memory.remember(channel.group, channel.id)
    }

    fun schedulePreview(channel: LiveChannel) {
        if (controller.alreadyShowing(channel.id, controller.state.streamIndex) &&
            controller.state.focusedChannelId == channel.id
        ) {
            controller.onChannelFocused(channel)
            syncSelectedGroupToChannel(channel.id)
            sync()
            return
        }
        val modeGeneration = controller.state.modeGeneration
        val generation = controller.onChannelFocused(channel)
        sync()
        previewJob?.cancel()
        previewJob = scope.launch {
            delay(LivePreviewPolicy.DEBOUNCE_MS)
            if (!controller.shouldApplyPreview(generation, channel.id, modeGeneration)) return@launch
            playStream(channel, streamIndex = 0, modeGeneration = modeGeneration)
        }
    }

    fun selectGroup(group: LiveGroup, playDefaultChannel: Boolean) {
        selectedGroupName = group.name
        focusColumn = LiveFocusColumn.GROUP
        if (!playDefaultChannel) return
        val rememberedInGroup = group.channels.firstOrNull { it.id == memory.lastChannelId }
        val target = rememberedInGroup ?: group.channels.firstOrNull() ?: return
        scope.launch {
            delay(16)
            focusColumn = LiveFocusColumn.CHANNEL
            runCatching { requesterFor(target.id).requestFocus() }
            schedulePreview(target)
        }
    }

    fun enterWatch() {
        previewJob?.cancel()
        controller.enterWatch()
        player.volume = 1f
        sync()
        osd = LiveOsdPolicy.watchLabel()
        // Anchor Selected to whatever is actually playing (or in-flight preview).
        syncSelectedGroupToChannel(
            controller.state.playingChannelId ?: controller.state.previewChannelId,
        )
        runCatching { watchFocus.requestFocus() }
    }

    fun revealBrowse() {
        previewJob?.cancel()
        controller.revealBrowseFromWatch()
        player.volume = 1f
        val targetId = controller.state.playingChannelId
            ?: controller.state.previewChannelId
            ?: controller.state.focusedChannelId
        syncSelectedGroupToChannel(targetId)
        sync()
        if (targetId != null) {
            scope.launch {
                delay(16)
                focusColumn = LiveFocusColumn.CHANNEL
                runCatching { requesterFor(targetId).requestFocus() }
            }
        }
    }

    val osdRef = rememberUpdatedState(osd)
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        controller.onPlayerBuffering()
                        sync()
                    }
                    Player.STATE_READY -> {
                        controller.onPlayerReady()
                        sync()
                        val shown = osdRef.value
                        if (shown.isNotEmpty()) {
                            scope.launch {
                                delay(LiveOsdPolicy.AUTO_HIDE_MS)
                                if (LiveOsdPolicy.shouldHide(osdRef.value, shown)) {
                                    osd = LiveOsdPolicy.watchLabel()
                                }
                            }
                        }
                    }
                    Player.STATE_IDLE -> Unit
                    Player.STATE_ENDED -> Unit
                }
            }

            override fun onRenderedFirstFrame() {
                controller.onFirstFrameRendered()
                syncSelectedGroupToChannel(controller.state.playingChannelId)
                sync()
            }

            override fun onPlayerError(error: PlaybackException) {
                val targetId = controller.state.previewChannelId ?: controller.state.playingChannelId
                val channel = groups.asSequence()
                    .flatMap { it.channels.asSequence() }
                    .firstOrNull { it.id == targetId }
                if (channel == null) {
                    controller.onPlayerError("无法播放")
                    sync()
                    return
                }
                val modeGeneration = controller.state.modeGeneration
                val next = controller.advanceStreamOrFail(channel.streams.size)
                sync()
                if (next != null) {
                    playStream(channel, next, modeGeneration = modeGeneration)
                } else {
                    osd = LiveOsdPolicy.errorLabel()
                }
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }

    fun reload() {
        scope.launch {
            loading = true
            val (result, err) = service.reload()
            groups = result
            loadError = err
            loading = false
        }
    }

    val visibleGroups = remember(groups) { LiveCatalog.visibleGroups(groups) }
    val selectedGroup = LiveCatalog.resolveSelection(visibleGroups, selectedGroupName)

    LaunchedEffect(Unit) { reload() }

    LaunchedEffect(visibleGroups) {
        if (visibleGroups.isEmpty()) {
            controller.markEmpty()
            sync()
            didInitialFocus = false
            return@LaunchedEffect
        }
        controller.markBrowseReady()
        sync()
        val rememberedGroup = memory.lastGroupName
            ?.takeIf { name -> visibleGroups.any { it.name == name } }
        val pick = LiveResume.resolve(visibleGroups, memory.lastChannelId)
        val groupName = rememberedGroup ?: pick?.group?.name ?: visibleGroups.first().name
        if (selectedGroupName != groupName) selectedGroupName = groupName
        if (!didInitialFocus) {
            didInitialFocus = true
            val channel = pick?.channel
                ?.takeIf { ch -> selectedGroup?.channels?.any { it.id == ch.id } == true }
                ?: selectedGroup?.channels?.firstOrNull()
                ?: pick?.channel
            if (channel != null) {
                scope.launch {
                    delay(32)
                    runCatching { requesterFor(channel.id).requestFocus() }
                    schedulePreview(channel)
                }
            } else {
                runCatching { groupFocus.requestFocus() }
            }
        }
    }

    LaunchedEffect(selectedGroup?.name) {
        channelListState.scrollToItem(0)
    }

    LaunchedEffect(liveState.uiMode) {
        if (liveState.uiMode == LiveUiMode.WATCH) {
            runCatching { watchFocus.requestFocus() }
        }
    }

    BackHandler(enabled = liveState.uiMode == LiveUiMode.WATCH) {
        revealBrowse()
    }
    BackHandler(enabled = liveState.uiMode == LiveUiMode.BROWSE && focusColumn == LiveFocusColumn.CHANNEL) {
        focusColumn = LiveFocusColumn.GROUP
        runCatching { groupFocus.requestFocus() }
    }
    BackHandler(enabled = liveState.uiMode == LiveUiMode.BROWSE && focusColumn == LiveFocusColumn.GROUP) {
        runCatching { sidebarLiveFocus.requestFocus() }
    }

    when {
        loading -> Centered { StatusText("加载直播源…") }
        visibleGroups.isEmpty() -> Centered {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                StatusText(loadError ?: "暂时没有可用频道")
                TvAction("重新加载") { reload() }
            }
        }
        selectedGroup == null -> Centered { StatusText("暂时没有可用频道") }
        else -> {
            val showSwitchVeil = !liveState.firstFrameRendered && (
                liveState.previewPhase == LivePreviewPhase.SWITCHING ||
                    liveState.playerPhase == LivePlayerPhase.PREPARING ||
                    liveState.playerPhase == LivePlayerPhase.BUFFERING
                )

            Box(Modifier.fillMaxSize().background(Color.Black)) {
                // Layer 1: single player surface — size locked to Live content area (no Sidebar teardown).
                LivePlayerSurface(player)

                if (showSwitchVeil) {
                    Box(Modifier.fillMaxSize().background(Color.Black))
                }

                if (showSwitchVeil ||
                    liveState.playerPhase == LivePlayerPhase.BUFFERING ||
                    liveState.playerPhase == LivePlayerPhase.PREPARING
                ) {
                    CircularProgressIndicator(
                        color = AppTheme.accent,
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .padding(24.dp),
                    )
                }

                val osdText = LiveOsdPolicy.visibleLabel(
                    osd,
                    watching = liveState.uiMode == LiveUiMode.WATCH,
                )
                if (osdText.isNotEmpty()) {
                    Text(
                        osdText,
                        color = Color.White,
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .padding(24.dp)
                            .background(Color.Black.copy(alpha = 0.55f))
                            .padding(horizontal = 14.dp, vertical = 8.dp),
                    )
                }

                if (liveState.errorMessage != null && liveState.playerPhase == LivePlayerPhase.ERROR) {
                    Text(
                        liveState.errorMessage ?: "无法播放",
                        color = Color.White,
                        modifier = Modifier
                            .align(Alignment.Center)
                            .background(Color.Black.copy(alpha = 0.65f))
                            .padding(horizontal = 20.dp, vertical = 12.dp),
                    )
                }

                if (liveState.chromeVisible) {
                    // Layer 2: full dim — prevents translucent columns from “slicing” the video.
                    Box(Modifier.fillMaxSize().background(BrowseDim))

                    // Leave room for MainActivity Sidebar overlay so columns aren't covered.
                    Row(
                        Modifier
                            .fillMaxSize()
                            .padding(
                                start = AppTheme.sidebarWidth + 12.dp,
                                top = 16.dp,
                                bottom = 16.dp,
                                end = 16.dp,
                            ),
                    ) {
                        LiveGroupColumn(
                            groups = visibleGroups,
                            selectedName = selectedGroup.name,
                            listState = groupListState,
                            itemShape = itemShape,
                            firstFocusRequester = groupFocus,
                            onSelectGroup = { selectGroup(it, playDefaultChannel = true) },
                            onFocused = { group ->
                                focusColumn = LiveFocusColumn.GROUP
                                // Focus on a group commits Selected so the channel list matches the highlight.
                                if (selectedGroupName != group.name) {
                                    selectedGroupName = group.name
                                }
                            },
                            onBackToSidebar = { runCatching { sidebarLiveFocus.requestFocus() } },
                            modifier = Modifier
                                .width(168.dp)
                                .fillMaxHeight()
                                .background(PanelScrim, itemShape)
                                .padding(vertical = 12.dp, horizontal = 8.dp),
                        )

                        LiveChannelColumn(
                            channels = selectedGroup.channels,
                            listState = channelListState,
                            itemShape = itemShape,
                            focusedChannelId = liveState.focusedChannelId,
                            playingChannelId = liveState.playingChannelId,
                            focusRequesterFor = ::requesterFor,
                            onChannelFocused = {
                                focusColumn = LiveFocusColumn.CHANNEL
                                schedulePreview(it)
                            },
                            onChannelConfirmed = { channel ->
                                previewJob?.cancel()
                                if (!controller.alreadyShowing(channel.id, 0)) {
                                    playStream(channel, 0)
                                }
                                enterWatch()
                            },
                            onBackToGroup = {
                                focusColumn = LiveFocusColumn.GROUP
                                runCatching { groupFocus.requestFocus() }
                            },
                            modifier = Modifier
                                .width(280.dp)
                                .fillMaxHeight()
                                .padding(start = 12.dp)
                                .background(PanelScrim, itemShape)
                                .padding(vertical = 12.dp, horizontal = 8.dp),
                        )
                    }
                } else {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .focusRequester(watchFocus)
                            .focusable()
                            .onPreviewKeyEvent { event ->
                                if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                                when (event.key) {
                                    Key.DirectionUp,
                                    Key.DirectionDown,
                                    Key.DirectionCenter,
                                    Key.Enter,
                                    Key.Menu,
                                    Key.ChannelUp,
                                    Key.ChannelDown,
                                    -> {
                                        revealBrowse()
                                        true
                                    }
                                    else -> false
                                }
                            },
                    )
                }
            }
        }
    }
}

@Composable
private fun LivePlayerSurface(player: ExoPlayer) {
    AndroidView(
        factory = { ctx ->
            (LayoutInflater.from(ctx).inflate(R.layout.player_surface, null) as PlayerView).apply {
                this.player = player
                useController = false
                setKeepContentOnPlayerReset(false)
                keepScreenOn = true
                if (LivePlayerPresentation.fillScreen) {
                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                }
                if (!LivePlayerPresentation.showTextTracks) {
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
            view.setKeepContentOnPlayerReset(false)
            if (LivePlayerPresentation.fillScreen) {
                view.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            }
            if (!LivePlayerPresentation.showTextTracks) {
                view.subtitleView?.visibility = android.view.View.GONE
            }
        },
        onRelease = { view ->
            view.player = null
        },
    )
}

@Composable
private fun LiveGroupColumn(
    groups: List<LiveGroup>,
    selectedName: String,
    listState: androidx.compose.foundation.lazy.LazyListState,
    itemShape: RoundedCornerShape,
    firstFocusRequester: FocusRequester,
    onSelectGroup: (LiveGroup) -> Unit,
    onFocused: (LiveGroup) -> Unit,
    onBackToSidebar: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        state = listState,
        modifier = modifier,
        contentPadding = PaddingValues(vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        itemsIndexed(groups, key = { _, group -> group.name }) { index, group ->
            val selected = group.name == selectedName
            Surface(
                onClick = { onSelectGroup(group) },
                colors = ClickableSurfaceDefaults.colors(
                    containerColor = if (selected) AppTheme.accent.copy(alpha = 0.45f) else Color.Transparent,
                    contentColor = if (selected) AppTheme.textPrimary else AppTheme.textSecondary,
                    focusedContainerColor = AppTheme.accent,
                    focusedContentColor = Color.Black,
                ),
                shape = ClickableSurfaceDefaults.shape(shape = itemShape),
                scale = ClickableSurfaceScale.None,
                border = ClickableSurfaceDefaults.border(
                    focusedBorder = Border(border = BorderStroke(2.dp, AppTheme.accent), shape = itemShape),
                ),
                modifier = Modifier
                    .fillParentMaxWidth()
                    .then(if (index == 0) Modifier.focusRequester(firstFocusRequester) else Modifier)
                    .onFocusChanged { if (it.isFocused) onFocused(group) }
                    .onPreviewKeyEvent { event ->
                        if (event.type == KeyEventType.KeyDown && event.key == Key.DirectionLeft) {
                            onBackToSidebar()
                            true
                        } else {
                            false
                        }
                    },
            ) {
                Text(
                    group.name,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 12.dp),
                )
            }
        }
    }
}

@Composable
private fun LiveChannelColumn(
    channels: List<LiveChannel>,
    listState: androidx.compose.foundation.lazy.LazyListState,
    itemShape: RoundedCornerShape,
    focusedChannelId: String?,
    playingChannelId: String?,
    focusRequesterFor: (String) -> FocusRequester,
    onChannelFocused: (LiveChannel) -> Unit,
    onChannelConfirmed: (LiveChannel) -> Unit,
    onBackToGroup: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        state = listState,
        modifier = modifier,
        contentPadding = PaddingValues(vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        itemsIndexed(channels, key = { _, channel -> channel.id }) { _, channel ->
            val playing = channel.id == playingChannelId
            Surface(
                onClick = { onChannelConfirmed(channel) },
                colors = ClickableSurfaceDefaults.colors(
                    containerColor = if (playing) Color.White.copy(alpha = 0.12f) else Color.Transparent,
                    contentColor = AppTheme.textSecondary,
                    focusedContainerColor = AppTheme.accent,
                    focusedContentColor = Color.Black,
                ),
                shape = ClickableSurfaceDefaults.shape(shape = itemShape),
                scale = ClickableSurfaceScale.None,
                border = ClickableSurfaceDefaults.border(
                    focusedBorder = Border(border = BorderStroke(2.dp, Color.White), shape = itemShape),
                ),
                modifier = Modifier
                    .fillParentMaxWidth()
                    .focusRequester(focusRequesterFor(channel.id))
                    .onFocusChanged { focusState ->
                        if (focusState.isFocused) onChannelFocused(channel)
                    }
                    .onPreviewKeyEvent { event ->
                        if (event.type == KeyEventType.KeyDown && event.key == Key.DirectionLeft) {
                            onBackToGroup()
                            true
                        } else {
                            false
                        }
                    },
            ) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        channel.name,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}
