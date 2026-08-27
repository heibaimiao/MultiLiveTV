package com.heibaimiao.multilivetv

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val json = Json { ignoreUnknownKeys = true }
        val retrofit = Retrofit.Builder()
            .baseUrl(ApiConfig.BASE_URL)
            .client(OkHttpClient.Builder().build())
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
        val api = retrofit.create(VodApi::class.java)

        setContent {
            MaterialTheme {
                HomeScreen(api)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(api: VodApi) {
    var keyword by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<VodItem>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var selectedDetail by remember { mutableStateOf<DetailResponse?>(null) }
    val scope = rememberCoroutineScope()

    Scaffold(topBar = { TopAppBar(title = { Text("MultiLiveTV") }) }) { padding ->
        Column(Modifier.padding(padding).padding(16.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = keyword,
                    onValueChange = { keyword = it },
                    modifier = Modifier.weight(1f),
                    label = { Text("搜索") },
                )
                Button(onClick = {
                    scope.launch {
                        try {
                            error = null
                            results = api.search(keyword).list
                        } catch (e: Exception) {
                            error = e.message
                        }
                    }
                }) { Text("搜索") }
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(results) { item ->
                    VodRow(item) {
                        scope.launch {
                            val sourceId = item.primarySourceId ?: item.variants?.firstOrNull()?.sourceId ?: 33
                            selectedDetail = api.detail(sourceId, item.vodId)
                        }
                    }
                }
            }
            selectedDetail?.let { detail ->
                AlertDialog(
                    onDismissRequest = { selectedDetail = null },
                    title = { Text(detail.vod.vodName) },
                    text = {
                        LazyColumn {
                            detail.playSources.forEach { source ->
                                item { Text(source.name, style = MaterialTheme.typography.titleSmall) }
                                items(source.episodes) { ep ->
                                    Text("• ${ep.name}", modifier = Modifier.padding(start = 8.dp))
                                }
                            }
                        }
                    },
                    confirmButton = {
                        TextButton(onClick = { selectedDetail = null }) { Text("关闭") }
                    },
                )
            }
        }
    }
}

@Composable
fun VodRow(item: VodItem, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AsyncImage(
            model = item.vodPic,
            contentDescription = item.vodName,
            modifier = Modifier.size(60.dp, 90.dp),
        )
        Column {
            Text(item.vodName, style = MaterialTheme.typography.titleMedium)
            item.vodRemarks?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
            item.variants?.size?.takeIf { it > 1 }?.let {
                Text("$it 个资源站", style = MaterialTheme.typography.labelSmall)
            }
        }
    }
}
