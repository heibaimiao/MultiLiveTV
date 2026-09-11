package com.heibaimiao.multilivetv.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

object AppTheme {
    val screenBackground = Color(0xFF0E0E10)
    val groupedBackground = Color(0xFF161618)
    val elevated = Color(0xFF202022)
    val accent = Color(0xFFED9E33)
    val textPrimary = Color.White
    val textSecondary = Color.White.copy(alpha = 0.72f)
    val textTertiary = Color.White.copy(alpha = 0.48f)
    val posterRadius = 8.dp
    val chipRadius = 6.dp
    val screenPadding = 20.dp
    val gridSpacing = 16.dp
    val cardMinWidth = 160.dp
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
    secondary = AppTheme.accent,
    error = Color(0xFFFF6B6B),
)

@Composable
fun MultiLiveTVTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = CinemaColors, content = content)
}
