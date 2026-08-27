import SwiftUI

@main
struct MultiLiveTVApp: App {
    @StateObject private var api = APIClient()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(api)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var api: APIClient

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }
            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            LoginView()
                .tabItem { Label(api.isLoggedIn ? "账户" : "登录", systemImage: "person") }
        }
        #if os(tvOS)
        .tabViewStyle(.sidebarAdaptable)
        #endif
    }
}
