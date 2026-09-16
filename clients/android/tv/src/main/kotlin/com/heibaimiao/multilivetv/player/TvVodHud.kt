package com.heibaimiao.multilivetv.player

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import com.heibaimiao.multilivetv.ui.AppTheme
import kotlin.math.roundToInt

@Composable
fun TvVodHud(
    visible: Boolean,
    playing: Boolean,
    positionMs: Long,
    durationMs: Long,
    bufferedMs: Long = 0L,
    modifier: Modifier = Modifier,
) {
    AnimatedVisibility(
        visible = visible,
        enter = fadeIn(),
        exit = fadeOut(),
        modifier = modifier,
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(
                        Brush.verticalGradient(
                            listOf(Color.Transparent, Color.Black.copy(alpha = 0.82f)),
                        ),
                    )
                    .padding(start = 48.dp, end = 48.dp, top = 40.dp, bottom = 24.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                Icon(
                    imageVector = if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    contentDescription = if (playing) "暂停" else "播放",
                    tint = Color.White,
                    modifier = Modifier.size(40.dp),
                )
                if (VodPlayerHud.showProgressBar(durationMs)) {
                    Text(
                        VodPlayerHud.formatClock(positionMs, durationMs),
                        color = Color.White,
                        fontSize = 16.sp,
                        modifier = Modifier.widthIn(min = 88.dp),
                    )
                    TvSeekBar(
                        positionMs = positionMs,
                        durationMs = durationMs,
                        bufferedMs = bufferedMs,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        VodPlayerHud.formatClock(durationMs, durationMs),
                        color = AppTheme.textSecondary,
                        fontSize = 16.sp,
                        textAlign = TextAlign.End,
                        modifier = Modifier.widthIn(min = 88.dp),
                    )
                } else {
                    Text("正在获取时长", color = AppTheme.textSecondary, fontSize = 16.sp)
                }
            }
        }
    }
}

@Composable
private fun TvSeekBar(
    positionMs: Long,
    durationMs: Long,
    bufferedMs: Long,
    modifier: Modifier = Modifier,
) {
    val fraction = VodPlayerHud.progressFraction(positionMs, durationMs)
    val buffered = VodPlayerHud.bufferedFraction(bufferedMs, durationMs)
    BoxWithConstraints(
        modifier.height(22.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(6.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(Color.White.copy(alpha = 0.22f)),
        )
        Box(
            Modifier
                .fillMaxWidth(buffered)
                .height(6.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(Color.White.copy(alpha = 0.72f)),
        )
        Box(
            Modifier
                .fillMaxWidth(fraction)
                .height(6.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(AppTheme.accent),
        )
        val thumbPx = with(LocalDensity.current) {
            VodPlayerHud.thumbOffsetPx(
                fraction = fraction,
                widthPx = maxWidth.toPx(),
                thumbSizePx = 16.dp.toPx(),
            )
        }
        Box(
            Modifier
                .offset { IntOffset(thumbPx.roundToInt(), 0) }
                .size(16.dp)
                .clip(CircleShape)
                .background(Color.White),
        )
    }
}
