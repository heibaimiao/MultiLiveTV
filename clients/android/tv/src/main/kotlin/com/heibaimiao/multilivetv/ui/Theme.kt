package com.heibaimiao.multilivetv.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.darkColorScheme

object AppTheme {
    val screenBackground = Color(0xFF0E0E10)
    val groupedBackground = Color(0xFF161618)
    val elevated = Color(0xFF202022)
    val accent = Color(0xFFED9E33)
    val textPrimary = Color.White
    val textSecondary = Color.White.copy(alpha = 0.72f)
    val textTertiary = Color.White.copy(alpha = 0.48f)
    val posterRadius = 8.dp
    val screenPadding = 32.dp
    val gridSpacing = 16.dp
    /** Global left nav width; Live browse chrome must clear this when Sidebar overlays video. */
    val sidebarWidth = 176.dp
}

private val CinemaColors = darkColorScheme(
    primary = AppTheme.accent,
    onPrimary = Color.Black,
    background = AppTheme.screenBackground,
    onBackground = AppTheme.textPrimary,
    surface = AppTheme.groupedBackground,
    onSurface = AppTheme.textPrimary,
    surfaceVariant = AppTheme.elevated,
    onSurfaceVariant = AppTheme.textSecondary,
    border = AppTheme.accent,
    borderVariant = Color.White.copy(alpha = 0.24f),
)

@Composable
fun MultiLiveTVTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = CinemaColors, content = content)
}
