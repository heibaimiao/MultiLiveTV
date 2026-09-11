package com.heibaimiao.multilivetv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.heibaimiao.multilivetv.category.SlugCategory

@Composable
fun CategoryTabs(
    primary: List<SlugCategory>,
    secondary: List<SlugCategory>,
    activeSlug: String?,
    activeParentSlug: String?,
    onSelect: (String?) -> Unit,
) {
    Column(Modifier.fillMaxWidth().background(AppTheme.screenBackground).padding(vertical = 8.dp)) {
        ChipRow(
            items = listOf(SlugCategory("all", "全部")) + primary,
            selected = { item ->
                if (item.slug == "all") activeSlug == null
                else activeSlug == item.slug || activeParentSlug == item.slug
            },
            onSelect = { item -> onSelect(if (item.slug == "all") null else item.slug) },
            accentSelected = false,
        )
        if (secondary.isNotEmpty() && activeParentSlug != null) {
            Spacer(Modifier.height(8.dp))
            ChipRow(
                items = listOf(SlugCategory(activeParentSlug, "全部")) + secondary,
                selected = { item ->
                    if (item.slug == activeParentSlug) activeSlug == activeParentSlug
                    else activeSlug == item.slug
                },
                onSelect = { item -> onSelect(item.slug) },
                accentSelected = true,
            )
        }
    }
}

@Composable
private fun ChipRow(
    items: List<SlugCategory>,
    selected: (SlugCategory) -> Boolean,
    onSelect: (SlugCategory) -> Unit,
    accentSelected: Boolean,
) {
    LazyRow(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = AppTheme.screenPadding),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(items, key = { "${it.slug}:${it.label}" }) { item ->
            CategoryChip(
                label = item.label,
                selected = selected(item),
                accent = accentSelected,
                onClick = { onSelect(item) },
            )
        }
    }
}

@Composable
private fun CategoryChip(
    label: String,
    selected: Boolean,
    accent: Boolean,
    onClick: () -> Unit,
) {
    val background = when {
        selected && accent -> AppTheme.accent
        selected -> AppTheme.elevated
        else -> Color.Transparent
    }
    val foreground = when {
        selected && accent -> Color.Black
        selected -> AppTheme.textPrimary
        else -> AppTheme.textSecondary
    }
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(AppTheme.chipRadius),
        color = background,
        modifier = Modifier.semantics { this.selected = selected },
    ) {
        Text(
            label,
            color = foreground,
            fontSize = 14.sp,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
        )
    }
}
