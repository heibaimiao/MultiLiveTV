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

#if os(tvOS)
@MainActor
final class AppLaunchSession: ObservableObject {
    enum Phase {
        case loading
        case ready(HomeLaunchPayload)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    private var loadGeneration = 0

    func load(using vod: VodService) async {
        loadGeneration += 1
        let generation = loadGeneration
        phase = .loading
        do {
            let payload = try await vod.loadHomeLaunch(tvDisplay: true)
            guard generation == loadGeneration else { return }
            if HomeLaunch.shouldEnterMain(didSucceed: true) {
                phase = .ready(payload)
            } else {
                phase = .failed("加载失败")
            }
        } catch {
            guard generation == loadGeneration else { return }
            phase = .failed(RequestFailure.userFacingMessage(for: error))
        }
    }
}
#endif

struct RootView: View {
    #if os(tvOS)
    @EnvironmentObject private var vod: VodService
    @StateObject private var launchSession = AppLaunchSession()
    #endif

    var body: some View {
        #if os(tvOS)
        tvRoot
        #else
        MainTabView()
        #endif
    }

    #if os(tvOS)
    @ViewBuilder
    private var tvRoot: some View {
        switch launchSession.phase {
        case .loading:
            LaunchLoadingView()
                .task { await launchSession.load(using: vod) }
        case .failed(let message):
            LaunchLoadingView(errorMessage: message) {
                Task { await launchSession.load(using: vod) }
            }
        case .ready(let payload):
            MainTabView(launch: payload)
        }
    }
    #endif
}

struct MainTabView: View {
    var launch: HomeLaunchPayload? = nil
    @EnvironmentObject private var deepLink: DeepLinkRouter

    var body: some View {
        TabView(selection: $deepLink.selectedTab) {
            HomeView(launch: launch)
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
