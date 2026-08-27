import SwiftUI

@main
struct MultiLiveTVApp: App {
    @StateObject private var vod = VodService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vod)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }
            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
        }
        .screenBackground()
        #if os(iOS)
        .modifier(IpadTabStyle())
        #endif
        #if os(tvOS)
        .modifier(TvOSTabStyle())
        #endif
    }
}

#if os(iOS)
private struct IpadTabStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}
#endif

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
