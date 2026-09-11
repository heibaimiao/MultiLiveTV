package com.heibaimiao.multilivetv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.heibaimiao.multilivetv.live.LiveChannel
import com.heibaimiao.multilivetv.live.LiveGroup
import com.heibaimiao.multilivetv.live.LiveService
import kotlinx.coroutines.launch

@Composable
fun LiveScreen(service: LiveService, onPlay: (LiveChannel) -> Unit) {
    var groups by remember { mutableStateOf<List<LiveGroup>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun reload() {
        scope.launch {
            loading = true
            val (result, err) = service.reload()
            groups = result
            error = err
            loading = false
        }
    }

    LaunchedEffect(Unit) { reload() }

    when {
        loading -> Centered { CircularProgressIndicator(color = AppTheme.accent) }
        error != null && groups.isEmpty() -> Centered {
            Column {
                Text(error!!, color = AppTheme.textSecondary)
                Button(onClick = { reload() }, modifier = Modifier.padding(AppTheme.screenPadding)) { Text("重试") }
            }
        }
        else -> LazyColumn(Modifier.fillMaxSize().background(AppTheme.screenBackground).padding(AppTheme.screenPadding)) {
            groups.forEach { group ->
                item { Text(group.name, color = AppTheme.accent, modifier = Modifier.padding(vertical = AppTheme.screenPadding / 2)) }
                items(group.channels, key = { it.id }) { channel ->
                    Text(
                        channel.name,
                        color = AppTheme.textPrimary,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onPlay(channel) }
                            .padding(vertical = 10.dp),
                    )
                }
            }
        }
    }
}
