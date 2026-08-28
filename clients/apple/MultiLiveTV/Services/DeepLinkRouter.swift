import Foundation
import Combine

enum AppTab: Hashable {
    case home
    case live
    case search
    case downloads
}

@MainActor
final class DeepLinkRouter: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var pendingVod: VodItem?

    func open(_ url: URL) {
        guard let target = AppDeepLink.parse(url) else { return }
        selectedTab = .home
        pendingVod = VodItem(
            vodId: target.vodId,
            vodName: "",
            vodPic: "",
            primarySourceId: target.sourceId
        )
    }
}
