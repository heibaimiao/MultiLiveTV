package com.heibaimiao.multilivetv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Button
import androidx.tv.material3.Text
import com.heibaimiao.multilivetv.model.VodItem
import com.heibaimiao.multilivetv.net.RequestFailure
import com.heibaimiao.multilivetv.vod.VodService
import kotlinx.coroutines.launch

@Composable
fun SearchScreen(vod: VodService, onOpen: (VodItem) -> Unit) {
    var keyword by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<VodItem>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var searched by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val posterFocusById = remember { mutableMapOf<String, FocusRequester>() }

    Column(Modifier.fillMaxSize().background(AppTheme.screenBackground).padding(top = AppTheme.screenPadding)) {
        Row(
            Modifier.padding(horizontal = AppTheme.screenPadding).fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            BasicTextField(
                value = keyword,
                onValueChange = { keyword = it },
                singleLine = true,
                cursorBrush = SolidColor(AppTheme.accent),
                textStyle = androidx.compose.ui.text.TextStyle(color = AppTheme.textPrimary),
                modifier = Modifier
                    .weight(1f)
                    .background(AppTheme.elevated)
                    .padding(16.dp),
                decorationBox = { inner ->
                    if (keyword.isEmpty()) Text("输入片名搜索", color = AppTheme.textTertiary)
                    inner()
                },
            )
            Button(
                onClick = {
                    if (keyword.isBlank()) return@Button
                    scope.launch {
                        loading = true
                        error = null
                        searched = true
                        try {
                            results = vod.search(keyword.trim())
                        } catch (e: Exception) {
                            error = RequestFailure.userFacingMessage(e)
                            results = emptyList()
                        } finally {
                            loading = false
                        }
                    }
                },
            ) { Text("搜索") }
        }
        when {
            loading -> Centered { StatusText("搜索中…") }
            error != null -> Centered { StatusText(error!!) }
            searched && results.isEmpty() -> Centered { StatusText("没有找到相关影片") }
            results.isNotEmpty() -> VodPosterGrid(
                items = results,
                onClick = onOpen,
                focusRequesterFor = { id -> posterFocusById.getOrPut(id) { FocusRequester() } },
                preferredFocusId = results.firstOrNull()?.id,
                onPosterNodesAttached = {
                    results.firstOrNull()?.id?.let { id ->
                        runCatching { posterFocusById.getOrPut(id) { FocusRequester() }.requestFocus() }
                    }
                },
            )
            else -> Centered { StatusText("输入片名后按搜索") }
        }
    }
}
