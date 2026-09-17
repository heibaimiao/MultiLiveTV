package com.heibaimiao.multilivetv

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.LiveTv
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import coil.Coil
import coil.ImageLoader
import com.heibaimiao.multilivetv.history.FileWatchHistoryPersistence
import com.heibaimiao.multilivetv.history.VodPlaybackRequest
import com.heibaimiao.multilivetv.history.WatchHistoryStore
import com.heibaimiao.multilivetv.live.LiveCatalog
import com.heibaimiao.multilivetv.live.LiveChannel
import com.heibaimiao.multilivetv.live.LiveService
import com.heibaimiao.multilivetv.model.VodItem
import com.heibaimiao.multilivetv.net.HttpClient
import com.heibaimiao.multilivetv.player.LivePlayerScreen
import com.heibaimiao.multilivetv.player.PlayerScreen
import com.heibaimiao.multilivetv.ui.AppTheme
import com.heibaimiao.multilivetv.ui.DetailScreen
import com.heibaimiao.multilivetv.ui.DownloadsScreen
import com.heibaimiao.multilivetv.ui.HistoryScreen
import com.heibaimiao.multilivetv.ui.HomeScreen
import com.heibaimiao.multilivetv.ui.LiveScreen
import com.heibaimiao.multilivetv.ui.MultiLiveTVTheme
import com.heibaimiao.multilivetv.ui.SearchScreen
import com.heibaimiao.multilivetv.vod.VodService
import java.io.File

class MainActivity : ComponentActivity() {
    @OptIn(ExperimentalMaterial3WindowSizeClassApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Coil.setImageLoader(
            ImageLoader.Builder(this)
                .okHttpClient { HttpClient.okHttp }
                .build(),
        )
        enableEdgeToEdge()
        AppContainer.ensureHistory(filesDir)
        val container = AppContainer
        setContent {
            MultiLiveTVTheme {
                val width = calculateWindowSizeClass(this).widthSizeClass
                MultiLiveTVApp(container, useRail = width != WindowWidthSizeClass.Compact)
            }
        }
    }
}

object AppContainer {
    val vod: VodService by lazy { VodService() }
    val live: LiveService by lazy { LiveService() }
    lateinit var history: WatchHistoryStore
        private set

    fun ensureHistory(filesDir: File) {
        if (::history.isInitialized) return
        history = WatchHistoryStore(FileWatchHistoryPersistence(File(filesDir, "watch_history.json")))
    }
}

private enum class Tab(val route: String, val label: String) {
    Home("home", "首页"),
    Live("live", "直播"),
    Search("search", "搜索"),
    History("history", "历史"),
    Downloads("downloads", "下载"),
}

@Composable
fun MultiLiveTVApp(container: AppContainer, useRail: Boolean) {
    val nav = rememberNavController()
    val backStack by nav.currentBackStackEntryAsState()
    val route = backStack?.destination?.route.orEmpty()
    val hideChrome = route.startsWith("player") || route.startsWith("livePlayer") || route.startsWith("detail")
    var pendingItem by remember { mutableStateOf<VodItem?>(null) }
    var pendingRequest by remember { mutableStateOf<VodPlaybackRequest?>(null) }
    var pendingLive by remember { mutableStateOf<LiveChannel?>(null) }
    val homeViewModel: HomeViewModel = viewModel(factory = HomeViewModelFactory(container.vod))

    val goTab: (Tab) -> Unit = { tab ->
        nav.navigate(tab.route) {
            popUpTo(nav.graph.findStartDestination().id) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }

    Scaffold(
        containerColor = AppTheme.screenBackground,
        bottomBar = {
            if (!useRail && !hideChrome) {
                NavigationBar(containerColor = AppTheme.groupedBackground) {
                    Tab.entries.forEach { tab ->
                        NavigationBarItem(
                            selected = route == tab.route,
                            onClick = { goTab(tab) },
                            icon = { Icon(tab.icon, tab.label) },
                            label = { Text(tab.label) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        Row(Modifier.fillMaxSize().padding(padding).background(AppTheme.screenBackground)) {
            if (useRail && !hideChrome) {
                NavigationRail(containerColor = AppTheme.groupedBackground) {
                    Tab.entries.forEach { tab ->
                        NavigationRailItem(
                            selected = route == tab.route,
                            onClick = { goTab(tab) },
                            icon = { Icon(tab.icon, tab.label) },
                            label = { Text(tab.label) },
                        )
                    }
                }
            }
            NavHost(navController = nav, startDestination = Tab.Home.route, modifier = Modifier.weight(1f)) {
                composable(Tab.Home.route) {
                    HomeScreen(homeViewModel) { item ->
                        pendingItem = item
                        nav.navigate("detail")
                    }
                }
                composable(Tab.Live.route) {
                    LiveScreen(container.live) { channel ->
                        pendingLive = channel
                        nav.navigate("livePlayer")
                    }
                }
                composable(Tab.Search.route) {
                    SearchScreen(container.vod) { item ->
                        pendingItem = item
                        nav.navigate("detail")
                    }
                }
                composable(Tab.History.route) {
                    HistoryScreen(container.history, container.vod) { request ->
                        pendingRequest = request
                        nav.navigate("player")
                    }
                }
                composable(Tab.Downloads.route) { DownloadsScreen() }
                composable("detail") {
                    val item = pendingItem
                    if (item == null) {
                        nav.popBackStack()
                    } else {
                        DetailScreen(
                            item = item,
                            vod = container.vod,
                            history = container.history,
                            onPlay = { request ->
                                pendingRequest = request
                                nav.navigate("player")
                            },
                            onBack = { nav.popBackStack() },
                        )
                    }
                }
                composable("player") {
                    val request = pendingRequest
                    if (request == null) {
                        nav.popBackStack()
                    } else {
                        PlayerScreen(request, container.vod, container.history) { nav.popBackStack() }
                    }
                }
                composable("livePlayer") {
                    val channel = pendingLive
                    if (channel == null) {
                        nav.popBackStack()
                    } else {
                        val stream = LiveCatalog.firstPlayableStream(channel)
                        if (stream == null) {
                            nav.popBackStack()
                        } else {
                            LivePlayerScreen(stream.url, stream.headers, channel.name) { nav.popBackStack() }
                        }
                    }
                }
            }
        }
    }
}

private val Tab.icon
    get() = when (this) {
        Tab.Home -> Icons.Outlined.Home
        Tab.Live -> Icons.Outlined.LiveTv
        Tab.Search -> Icons.Outlined.Search
        Tab.History -> Icons.Outlined.History
        Tab.Downloads -> Icons.Outlined.Download
    }

class HomeViewModelFactory(private val vod: VodService) : androidx.lifecycle.ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T = HomeViewModel(vod) as T
}
