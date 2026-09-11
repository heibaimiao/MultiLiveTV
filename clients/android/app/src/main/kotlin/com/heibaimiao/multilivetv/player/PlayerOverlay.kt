package com.heibaimiao.multilivetv.player

import android.app.Activity
import android.content.pm.ActivityInfo
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.FullscreenExit
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import com.heibaimiao.multilivetv.parser.PlaybackSeek
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

private const val HideAfterMs = 3_200L
private const val FlashMs = 700L

@Composable
fun CinemaPlayerOverlay(
    player: ExoPlayer,
    title: String,
    subtitle: String? = null,
    isLive: Boolean = false,
    playerView: PlayerView? = null,
    onClose: () -> Unit,
) {
    var controlsVisible by remember { mutableStateOf(true) }
    var isPlaying by remember { mutableStateOf(player.isPlaying) }
    var buffering by remember { mutableStateOf(player.playbackState == Player.STATE_BUFFERING) }
    var positionMs by remember { mutableLongStateOf(0L) }
    var durationMs by remember { mutableLongStateOf(0L) }
    var muted by remember { mutableStateOf(player.volume == 0f) }
    var lastVolume by remember { mutableFloatStateOf(if (player.volume > 0f) player.volume else 1f) }
    var scrubbing by remember { mutableStateOf(false) }
    var scrubMs by remember { mutableLongStateOf(0L) }
    var dragSeeking by remember { mutableStateOf(false) }
    var dragStartMs by remember { mutableLongStateOf(0L) }
    var dragPx by remember { mutableFloatStateOf(0f) }
    var dragWidthPx by remember { mutableFloatStateOf(1f) }
    var flashStep by remember { mutableStateOf<Int?>(null) }
    var landscape by remember { mutableStateOf(false) }
    val activity = LocalContext.current as? Activity

    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                buffering = playbackState == Player.STATE_BUFFERING
            }

            override fun onVolumeChanged(volume: Float) {
                muted = volume == 0f
                if (volume > 0f) lastVolume = volume
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }

    DisposableEffect(activity) {
        onDispose { applyFullscreen(activity, playerView, false) }
    }

    LaunchedEffect(player) {
        while (true) {
            if (!scrubbing && !dragSeeking) {
                positionMs = player.currentPosition.coerceAtLeast(0L)
                val duration = player.duration
                durationMs = if (duration > 0L) duration else 0L
            }
            delay(250)
        }
    }

    LaunchedEffect(controlsVisible, isPlaying, scrubbing, dragSeeking) {
        if (controlsVisible && isPlaying && !scrubbing && !dragSeeking) {
            delay(HideAfterMs)
            controlsVisible = false
        }
    }

    LaunchedEffect(flashStep) {
        if (flashStep != null) {
            delay(FlashMs)
            flashStep = null
        }
    }

    val displayMs = when {
        dragSeeking -> PlaybackSeek.targetFromDrag(dragStartMs, durationMs, dragPx, dragWidthPx)
        scrubbing -> scrubMs
        else -> positionMs
    }

    Box(
        Modifier
            .fillMaxSize()
            .pointerInput(isLive, durationMs) {
                detectTapGestures(
                    onDoubleTap = { offset ->
                        if (isLive) {
                            if (player.isPlaying) player.pause() else player.play()
                            controlsVisible = true
                            return@detectTapGestures
                        }
                        val zone = PlaybackSeek.tapZone(offset.x, size.width.toFloat())
                        val target = PlaybackSeek.doubleTapTarget(player.currentPosition, durationMs.coerceAtLeast(0L), zone)
                        if (target == null) {
                            if (player.isPlaying) player.pause() else player.play()
                        } else {
                            player.seekTo(target)
                            flashStep = if (zone == PlaybackSeek.TapZone.Rewind) -10 else 10
                        }
                        controlsVisible = true
                    },
                    onTap = { controlsVisible = !controlsVisible },
                )
            }
            .pointerInput(isLive, durationMs) {
                if (isLive) return@pointerInput
                detectHorizontalDragGestures(
                    onDragStart = {
                        dragStartMs = player.currentPosition.coerceAtLeast(0L)
                        dragPx = 0f
                        dragWidthPx = size.width.toFloat().coerceAtLeast(1f)
                        dragSeeking = true
                    },
                    onHorizontalDrag = { change, amount ->
                        change.consume()
                        dragPx += amount
                    },
                    onDragEnd = {
                        player.seekTo(PlaybackSeek.targetFromDrag(dragStartMs, durationMs, dragPx, dragWidthPx))
                        dragSeeking = false
                    },
                    onDragCancel = { dragSeeking = false },
                )
            },
    ) {
        if (buffering && !dragSeeking) {
            CircularProgressIndicator(
                color = Color.White,
                modifier = Modifier
                    .size(36.dp)
                    .align(Alignment.Center),
                strokeWidth = 3.dp,
            )
        }

        if (dragSeeking && !isLive) {
            DragSeekHud(
                startMs = dragStartMs,
                targetMs = displayMs,
                durationMs = durationMs,
                modifier = Modifier.align(Alignment.Center),
            )
        }

        flashStep?.let { step ->
            Text(
                if (step < 0) "−10" else "+10",
                color = Color.White,
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .align(if (step < 0) Alignment.CenterStart else Alignment.CenterEnd)
                    .padding(horizontal = 48.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(Color.Black.copy(alpha = 0.45f))
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }

        AnimatedVisibility(
            visible = controlsVisible && !dragSeeking,
            enter = fadeIn(),
            exit = fadeOut(),
        ) {
            Box(Modifier.fillMaxSize()) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(120.dp)
                        .align(Alignment.TopCenter)
                        .background(
                            Brush.verticalGradient(
                                0f to Color.Black.copy(alpha = 0.72f),
                                1f to Color.Transparent,
                            ),
                        ),
                )
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(140.dp)
                        .align(Alignment.BottomCenter)
                        .background(
                            Brush.verticalGradient(
                                0f to Color.Transparent,
                                1f to Color.Black.copy(alpha = 0.82f),
                            ),
                        ),
                )

                Row(
                    Modifier
                        .fillMaxWidth()
                        .statusBarsPadding()
                        .padding(horizontal = 4.dp)
                        .align(Alignment.TopStart),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = onClose) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "关闭", tint = Color.White)
                    }
                    Column(Modifier.weight(1f).padding(end = 8.dp)) {
                        Text(
                            title.ifBlank { "正在播放" },
                            color = Color.White,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        if (!subtitle.isNullOrBlank()) {
                            Text(subtitle, color = Color.White.copy(alpha = 0.72f), fontSize = 12.sp, maxLines = 1)
                        }
                    }
                }

                Column(
                    Modifier
                        .fillMaxWidth()
                        .align(Alignment.BottomCenter)
                        .navigationBarsPadding()
                        .padding(start = 12.dp, end = 8.dp, bottom = 10.dp),
                ) {
                    if (!isLive && durationMs > 0L) {
                        ScrubBar(
                            positionMs = displayMs,
                            durationMs = durationMs,
                            onScrub = {
                                scrubbing = true
                                scrubMs = it
                                controlsVisible = true
                            },
                            onScrubEnd = {
                                player.seekTo(it)
                                positionMs = it
                                scrubbing = false
                            },
                        )
                    }
                    Row(
                        Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconButton(
                            onClick = {
                                if (isPlaying) player.pause() else player.play()
                                controlsVisible = true
                            },
                        ) {
                            Icon(
                                imageVector = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                                contentDescription = if (isPlaying) "暂停" else "播放",
                                tint = Color.White,
                            )
                        }
                        Text(
                            if (isLive) "直播中" else "${formatPlaybackTime(displayMs)} / ${formatPlaybackTime(durationMs)}",
                            color = Color.White,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium,
                        )
                        Spacer(Modifier.weight(1f))
                        IconButton(
                            onClick = {
                                if (player.volume > 0f) {
                                    lastVolume = player.volume
                                    player.volume = 0f
                                } else {
                                    player.volume = lastVolume.coerceAtLeast(0.25f)
                                }
                                controlsVisible = true
                            },
                        ) {
                            Icon(
                                imageVector = if (muted) Icons.AutoMirrored.Filled.VolumeOff else Icons.AutoMirrored.Filled.VolumeUp,
                                contentDescription = if (muted) "取消静音" else "静音",
                                tint = Color.White,
                            )
                        }
                        IconButton(
                            onClick = {
                                landscape = !landscape
                                applyFullscreen(activity, playerView, landscape)
                                controlsVisible = true
                            },
                        ) {
                            Icon(
                                imageVector = if (landscape) Icons.Filled.FullscreenExit else Icons.Filled.Fullscreen,
                                contentDescription = if (landscape) "退出全屏" else "全屏",
                                tint = Color.White,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DragSeekHud(
    startMs: Long,
    targetMs: Long,
    durationMs: Long,
    modifier: Modifier = Modifier,
) {
    val delta = targetMs - startMs
    val sign = if (delta >= 0) "+" else "−"
    Column(
        modifier
            .clip(RoundedCornerShape(10.dp))
            .background(Color.Black.copy(alpha = 0.55f))
            .padding(horizontal = 20.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            "$sign${formatPlaybackTime(abs(delta))}",
            color = Color.White,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
        )
        Text(
            "${formatPlaybackTime(targetMs)} / ${formatPlaybackTime(durationMs)}",
            color = Color.White.copy(alpha = 0.8f),
            fontSize = 13.sp,
        )
        Box(
            Modifier
                .width(180.dp)
                .height(3.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(Color.White.copy(alpha = 0.24f)),
        ) {
            val fraction = if (durationMs > 0L) (targetMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f
            Box(
                Modifier
                    .fillMaxWidth(fraction)
                    .height(3.dp)
                    .background(Color.White),
            )
        }
    }
}

@Composable
private fun ScrubBar(
    positionMs: Long,
    durationMs: Long,
    onScrub: (Long) -> Unit,
    onScrubEnd: (Long) -> Unit,
) {
    val fraction = if (durationMs > 0L) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .height(28.dp)
            .pointerInput(durationMs) {
                detectTapGestures { offset ->
                    val target = PlaybackSeek.targetFromDrag(0L, durationMs, offset.x, size.width.toFloat())
                    onScrub(target)
                    onScrubEnd(target)
                }
            }
            .pointerInput(durationMs) {
                var last = positionMs
                detectHorizontalDragGestures(
                    onDragStart = { offset ->
                        last = PlaybackSeek.targetFromDrag(0L, durationMs, offset.x, size.width.toFloat())
                        onScrub(last)
                    },
                    onHorizontalDrag = { change, _ ->
                        change.consume()
                        last = PlaybackSeek.targetFromDrag(0L, durationMs, change.position.x, size.width.toFloat())
                        onScrub(last)
                    },
                    onDragEnd = { onScrubEnd(last) },
                    onDragCancel = { onScrubEnd(last) },
                )
            },
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(3.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(Color.White.copy(alpha = 0.28f)),
        )
        Box(
            Modifier
                .fillMaxWidth(fraction)
                .height(3.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(Color.White),
        )
        val thumbPx = with(LocalDensity.current) { (maxWidth * fraction).toPx() }
        Box(
            Modifier
                .offset { IntOffset((thumbPx - 6.dp.toPx()).roundToInt(), 0) }
                .size(12.dp)
                .clip(CircleShape)
                .background(Color.White),
        )
    }
}

private fun applyFullscreen(activity: Activity?, playerView: PlayerView?, enabled: Boolean) {
    val window = activity?.window ?: return
    activity.requestedOrientation = if (enabled) {
        ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
    } else {
        ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    }
    playerView?.resizeMode = if (enabled) {
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM
    } else {
        AspectRatioFrameLayout.RESIZE_MODE_FIT
    }
    WindowInsetsControllerCompat(window, window.decorView).apply {
        if (enabled) {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        } else {
            show(WindowInsetsCompat.Type.systemBars())
        }
    }
}

internal fun formatPlaybackTime(ms: Long): String {
    if (ms <= 0L) return "00:00"
    val totalSeconds = ms / 1000
    val hours = totalSeconds / 3600
    val minutes = (totalSeconds % 3600) / 60
    val seconds = totalSeconds % 60
    return if (hours > 0) {
        "%d:%02d:%02d".format(hours, minutes, seconds)
    } else {
        "%02d:%02d".format(minutes, seconds)
    }
}
