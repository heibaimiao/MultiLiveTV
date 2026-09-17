package com.heibaimiao.multilivetv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.heibaimiao.multilivetv.model.VodItem
import com.heibaimiao.multilivetv.net.RequestFailure
import com.heibaimiao.multilivetv.net.RequestGeneration
import com.heibaimiao.multilivetv.vod.VodService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

@Composable
fun SearchScreen(vod: VodService, onOpen: (VodItem) -> Unit) {
    var keyword by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<VodItem>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var searched by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val generation = remember { RequestGeneration() }
    var searchJob by remember { mutableStateOf<Job?>(null) }

    fun runSearch() {
        if (keyword.isBlank()) return
        searchJob?.cancel()
        searchJob = scope.launch {
            val token = generation.next()
            loading = true
            error = null
            searched = true
            try {
                val found = vod.search(keyword.trim())
                if (!generation.shouldApply(token)) return@launch
                results = found
                error = null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!generation.shouldApply(token)) return@launch
                error = RequestFailure.userFacingMessage(e)
                results = emptyList()
            } finally {
                if (generation.shouldApply(token)) loading = false
            }
        }
    }

    Column(Modifier.fillMaxSize().background(AppTheme.screenBackground).padding(top = AppTheme.screenPadding)) {
        Row(
            Modifier.padding(horizontal = AppTheme.screenPadding),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = keyword,
                onValueChange = { keyword = it },
                modifier = Modifier.weight(1f),
                singleLine = true,
                label = { Text("搜索") },
            )
            Button(onClick = { runSearch() }) { Text("搜索") }
        }
        when {
            loading -> Centered { CircularProgressIndicator(color = AppTheme.accent) }
            error != null -> Centered {
                Column {
                    Text(error!!, color = AppTheme.textSecondary)
                    Button(onClick = { runSearch() }, modifier = Modifier.padding(top = 12.dp)) { Text("重试") }
                }
            }
            searched && results.isEmpty() -> Centered { Text("没有找到相关影片", color = AppTheme.textSecondary) }
            results.isNotEmpty() -> VodPosterGrid(results, onOpen)
            else -> Centered { Text("输入片名搜索多源结果", color = AppTheme.textTertiary) }
        }
    }
}
