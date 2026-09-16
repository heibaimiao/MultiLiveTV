package com.heibaimiao.multilivetv.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.unit.dp
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import com.heibaimiao.multilivetv.category.SlugCategory
import com.heibaimiao.multilivetv.ui.HomeFocusPolicy

@Composable
fun CategoryTabs(
    primary: List<SlugCategory>,
    secondary: List<SlugCategory>,
    activeSlug: String?,
    activeParentSlug: String?,
    onSelect: (String?) -> Unit,
    /** Used only for programmatic Back-from-grid restore; not equivalent to "must keep focus here". */
    landingFocusRequester: FocusRequester,
    /** @return true when focus successfully moved into the poster grid. */
    onMoveDownToContent: () -> Boolean,
    onBackToSidebar: () -> Unit,
) {
    var focused by remember { mutableStateOf(false) }
    BackHandler(enabled = focused) { onBackToSidebar() }

    Column(
        Modifier
            .fillMaxWidth()
            .padding(bottom = 12.dp)
            .onFocusChanged { focused = it.hasFocus },
    ) {
        val primaryItems = listOf(SlugCategory("all", "全部")) + primary
        val hasSecondary = secondary.isNotEmpty() && activeParentSlug != null
        ChipRow(
            items = primaryItems,
            selected = { item ->
                if (item.slug == "all") activeSlug == null
                else activeSlug == item.slug || activeParentSlug == item.slug
            },
            onSelect = { item -> onSelect(if (item.slug == "all") null else item.slug) },
            landingFocusRequester = if (hasSecondary) null else landingFocusRequester,
            onMoveDown = onMoveDownToContent,
        )
        if (hasSecondary) {
            ChipRow(
                items = listOf(SlugCategory(activeParentSlug!!, "全部")) + secondary,
                selected = { item ->
                    if (item.slug == activeParentSlug) activeSlug == activeParentSlug
                    else activeSlug == item.slug
                },
                onSelect = { item -> onSelect(item.slug) },
                landingFocusRequester = landingFocusRequester,
                onMoveDown = onMoveDownToContent,
            )
        }
    }
}

@Composable
private fun ChipRow(
    items: List<SlugCategory>,
    selected: (SlugCategory) -> Boolean,
    onSelect: (SlugCategory) -> Unit,
    landingFocusRequester: FocusRequester?,
    onMoveDown: () -> Boolean,
) {
    LazyRow(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        contentPadding = PaddingValues(horizontal = AppTheme.screenPadding),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        itemsIndexed(items, key = { _, item -> "${item.slug}:${item.label}" }) { _, item ->
            val isSelected = selected(item)
            Surface(
                onClick = { onSelect(item) },
                colors = ClickableSurfaceDefaults.colors(
                    containerColor = if (isSelected) AppTheme.accent else AppTheme.elevated,
                    contentColor = if (isSelected) androidx.compose.ui.graphics.Color.Black else AppTheme.textSecondary,
                    focusedContainerColor = if (isSelected) AppTheme.accent else AppTheme.groupedBackground,
                    focusedContentColor = if (isSelected) androidx.compose.ui.graphics.Color.Black else AppTheme.textPrimary,
                ),
                modifier = Modifier
                    .then(
                        if (isSelected && landingFocusRequester != null) {
                            Modifier.focusRequester(landingFocusRequester)
                        } else {
                            Modifier
                        },
                    )
                    .onPreviewKeyEvent { event ->
                        if (event.type != KeyEventType.KeyDown || event.key != Key.DirectionDown) {
                            return@onPreviewKeyEvent false
                        }
                        val moved = onMoveDown()
                        // Consume only on success so a failed requestFocus cannot permanently block Focus Search.
                        HomeFocusPolicy.shouldConsumeDirectionDown(moved)
                    },
            ) {
                Text(item.label, modifier = Modifier.padding(horizontal = 18.dp, vertical = 10.dp))
            }
        }
    }
}
