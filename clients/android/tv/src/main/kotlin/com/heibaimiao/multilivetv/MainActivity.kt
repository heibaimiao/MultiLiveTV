package com.heibaimiao.multilivetv

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.LiveTv
import androidx.compose.material.icons.outlined.Search
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.tv.material3.Border
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.ClickableSurfaceScale
import androidx.tv.material3.Icon
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import coil.Coil
import coil.ImageLoader
import com.heibaimiao.multilivetv.history.FileWatchHistoryPersistence
import com.heibaimiao.multilivetv.history.VodPlaybackRequest
import com.heibaimiao.multilivetv.history.WatchHistoryStore
import com.heibaimiao.multilivetv.live.LiveService
import com.heibaimiao.multilivetv.live.PrefsLiveChannelMemory
import com.heibaimiao.multilivetv.model.VodItem
import com.heibaimiao.multilivetv.net.HttpClient
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
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Coil.setImageLoader(
            ImageLoader.Builder(this)
                .okHttpClient { HttpClient.okHttp }
                .build(),
        )
        AppContainer.ensureHistory(filesDir)
        val container = AppContainer
        setContent {
            MultiLiveTVTheme {
                MultiLiveTVApp(container)
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
fun MultiLiveTVApp(container: AppContainer) {
    val context = LocalContext.current
    val nav = rememberNavController()
    val backStack by nav.currentBackStackEntryAsState()
    val route = backStack?.destination?.route.orEmpty()
    var liveWatching by remember { mutableStateOf(false) }
    val isLiveRoute = route == Tab.Live.route
    // player/detail: no sidebar. Live WATCH: no sidebar (player stays full-bleed).
    val hideChrome = route.startsWith("player") || route.startsWith("detail")
    val showSidebarInRow = !hideChrome && !isLiveRoute
    val showSidebarOverlay = isLiveRoute && !liveWatching
    var pendingItem by remember { mutableStateOf<VodItem?>(null) }
    var pendingRequest by remember { mutableStateOf<VodPlaybackRequest?>(null) }
    var lastOpenedPosterId by remember { mutableStateOf<String?>(null) }
    var restoreHomePosterId by remember { mutableStateOf<String?>(null) }
    val homeViewModel: HomeViewModel = viewModel(factory = HomeViewModelFactory(container.vod))
    val sidebarHomeFocus = remember { FocusRequester() }
    val sidebarLiveFocus = remember { FocusRequester() }
    val liveMemory = remember { PrefsLiveChannelMemory(context) }

    LaunchedEffect(route) {
        if (route != Tab.Live.route) liveWatching = false
    }

    val goTab: (Tab) -> Unit = { tab ->
        nav.navigate(tab.route) {
            popUpTo(nav.graph.findStartDestination().id) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }

    Box(Modifier.fillMaxSize().background(AppTheme.screenBackground)) {
        // Live: NavHost is full width so the player never shares space with Sidebar.
        // Other tabs: Sidebar sits in the Row and takes sidebarWidth.
        Row(Modifier.fillMaxSize()) {
            if (showSidebarInRow) {
                AppSidebar(
                    route = route,
                    sidebarHomeFocus = sidebarHomeFocus,
                    sidebarLiveFocus = sidebarLiveFocus,
                    onTab = goTab,
                )
            }
            AppNavHost(
                nav = nav,
                container = container,
                homeViewModel = homeViewModel,
                liveMemory = liveMemory,
                sidebarHomeFocus = sidebarHomeFocus,
                sidebarLiveFocus = sidebarLiveFocus,
                restoreHomePosterId = restoreHomePosterId,
                onRestoreHomePosterId = { restoreHomePosterId = null },
                onOpenDetail = { item ->
                    lastOpenedPosterId = item.id
                    pendingItem = item
                    nav.navigate("detail")
                },
                onDetailBack = {
                    restoreHomePosterId = lastOpenedPosterId
                    nav.popBackStack()
                },
                pendingItem = pendingItem,
                onPendingItem = { pendingItem = it },
                pendingRequest = pendingRequest,
                onPendingRequest = { pendingRequest = it },
                onWatchModeChanged = { liveWatching = it },
                modifier = Modifier.weight(1f).fillMaxSize(),
            )
        }
        // Live browse: Sidebar overlays video; WATCH removes it without resizing the player.
        if (showSidebarOverlay) {
            AppSidebar(
                route = route,
                sidebarHomeFocus = sidebarHomeFocus,
                sidebarLiveFocus = sidebarLiveFocus,
                onTab = goTab,
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .fillMaxHeight(),
            )
        }
    }
}

@Composable
private fun AppSidebar(
    route: String,
    sidebarHomeFocus: FocusRequester,
    sidebarLiveFocus: FocusRequester,
    onTab: (Tab) -> Unit,
    modifier: Modifier = Modifier,
) {
    val itemShape = RoundedCornerShape(8.dp)
    Column(
        modifier
            .width(AppTheme.sidebarWidth)
            .fillMaxHeight()
            .background(AppTheme.groupedBackground)
            .padding(vertical = 24.dp, horizontal = 8.dp),
    ) {
        Text("MultiLiveTV", color = AppTheme.textPrimary, modifier = Modifier.padding(8.dp))
        Tab.entries.forEach { tab ->
            val selected = route == tab.route
            Surface(
                onClick = { onTab(tab) },
                colors = ClickableSurfaceDefaults.colors(
                    containerColor = if (selected) AppTheme.elevated else AppTheme.groupedBackground,
                    contentColor = if (selected) AppTheme.accent else AppTheme.textSecondary,
                    focusedContainerColor = AppTheme.accent,
                    focusedContentColor = androidx.compose.ui.graphics.Color.Black,
                ),
                shape = ClickableSurfaceDefaults.shape(shape = itemShape),
                scale = ClickableSurfaceScale.None,
                border = ClickableSurfaceDefaults.border(
                    focusedBorder = Border(
                        border = BorderStroke(2.dp, AppTheme.accent),
                        shape = itemShape,
                    ),
                ),
                modifier = Modifier
                    .padding(vertical = 6.dp)
                    .fillMaxWidth()
                    .then(
                        when (tab) {
                            Tab.Home -> Modifier.focusRequester(sidebarHomeFocus)
                            Tab.Live -> Modifier.focusRequester(sidebarLiveFocus)
                            else -> Modifier
                        },
                    ),
            ) {
                Row(
                    Modifier.padding(horizontal = 12.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(tab.icon, contentDescription = null)
                    Text(tab.label, modifier = Modifier.padding(start = 12.dp))
                }
            }
        }
    }
}

@Composable
private fun AppNavHost(
    nav: NavHostController,
    container: AppContainer,
    homeViewModel: HomeViewModel,
    liveMemory: PrefsLiveChannelMemory,
    sidebarHomeFocus: FocusRequester,
    sidebarLiveFocus: FocusRequester,
    restoreHomePosterId: String?,
    onRestoreHomePosterId: () -> Unit,
    onOpenDetail: (VodItem) -> Unit,
    onDetailBack: () -> Unit,
    pendingItem: VodItem?,
    onPendingItem: (VodItem?) -> Unit,
    pendingRequest: VodPlaybackRequest?,
    onPendingRequest: (VodPlaybackRequest?) -> Unit,
    onWatchModeChanged: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    NavHost(navController = nav, startDestination = Tab.Home.route, modifier = modifier) {
        composable(Tab.Home.route) {
            HomeScreen(
                viewModel = homeViewModel,
                sidebarHomeFocus = sidebarHomeFocus,
                restorePosterId = restoreHomePosterId,
                onPosterRestored = onRestoreHomePosterId,
                onOpen = onOpenDetail,
            )
        }
        composable(Tab.Live.route) {
            LiveScreen(
                service = container.live,
                memory = liveMemory,
                sidebarLiveFocus = sidebarLiveFocus,
                onWatchModeChanged = onWatchModeChanged,
            )
        }
        composable(Tab.Search.route) {
            SearchScreen(container.vod) { item ->
                onPendingItem(item)
                nav.navigate("detail")
            }
        }
        composable(Tab.History.route) {
            HistoryScreen(container.history, container.vod) { request ->
                onPendingRequest(request)
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
                        onPendingRequest(request)
                        nav.navigate("player")
                    },
                    onBack = onDetailBack,
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
