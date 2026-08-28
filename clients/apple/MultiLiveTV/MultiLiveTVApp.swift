import SwiftUI
#if os(iOS) || os(tvOS)
import UIKit
#endif

@main
struct MultiLiveTVApp: App {
    #if os(iOS) || os(tvOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @StateObject private var vod: VodService
    @StateObject private var downloads: DownloadManager
    @StateObject private var deepLink = DeepLinkRouter()

    init() {
        let vodService = VodService()
        _vod = StateObject(wrappedValue: vodService)
        _downloads = StateObject(wrappedValue: DownloadManager(parser: vodService))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vod)
                .environmentObject(downloads)
                .environmentObject(deepLink)
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
                .onOpenURL { deepLink.open($0) }
                .task {
                    await downloads.restore()
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        DownloadManager.backgroundSessionOwner?.handleBackgroundEvents(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }
}

struct RootView: View {
    var body: some View {
        MainTabView()
    }
}

struct MainTabView: View {
    @EnvironmentObject private var deepLink: DeepLinkRouter

    var body: some View {
        TabView(selection: $deepLink.selectedTab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }
                .tag(AppTab.home)
            LiveView()
                .tabItem { Label("直播", systemImage: "dot.radiowaves.left.and.right") }
                .tag(AppTab.live)
            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
            DownloadsView()
                .tabItem { Label("下载", systemImage: "arrow.down.circle") }
                .tag(AppTab.downloads)
        }
        .screenBackground()
        #if os(tvOS)
        .modifier(TvOSTabStyle())
        #endif
    }
}

#if os(tvOS)
private struct TvOSTabStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(tvOS 18.0, *) {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}
#endif
