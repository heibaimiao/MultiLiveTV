import Foundation

@MainActor
final class LiveService: ObservableObject {
    @Published private(set) var groups: [LiveGroup] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let store: LiveStore
    private let session: URLSession
    private var reloadGeneration = 0
    private let storeError: String?

    var hasConfiguredSource: Bool {
        !store.enabled().isEmpty
    }

    var configurationError: String? { storeError }

    init(store: LiveStore? = nil) {
        if let store {
            self.store = store
            storeError = nil
        } else {
            do {
                self.store = try LiveStore()
                storeError = nil
            } catch {
                self.store = LiveStore(sources: [])
                storeError = error.localizedDescription
            }
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = NetworkConfig.requestTimeout
        config.timeoutIntervalForResource = max(NetworkConfig.requestTimeout, 60)
        config.httpAdditionalHeaders = ["User-Agent": NetworkConfig.userAgent]
        session = URLSession(configuration: config)
    }

    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        errorMessage = nil
        let sources = store.enabled()
        guard !sources.isEmpty else {
            groups = []
            errorMessage = storeError ?? LiveError.notConfigured.localizedDescription
            return
        }

        isLoading = true
        defer {
            if generation == reloadGeneration {
                isLoading = false
            }
        }

        var playlists: [[LiveGroup]] = []
        var lastError: String?
        for source in sources {
            do {
                playlists.append(try await fetchPlaylist(source.url))
            } catch {
                lastError = RequestFailure.userFacingMessage(for: error)
            }
        }
        guard generation == reloadGeneration else { return }

        let merged = M3UPlaylistParser.merge(playlists)
        if merged.isEmpty {
            groups = []
            errorMessage = lastError ?? LiveError.emptyPlaylist.localizedDescription
        } else {
            groups = merged
            errorMessage = nil
        }
    }

    private func fetchPlaylist(_ urlString: String) async throws -> [LiveGroup] {
        guard let url = RemoteMediaURL.parse(urlString) ?? URL(string: urlString) else {
            throw LiveError.notConfigured
        }
        let (data, response) = try await session.data(from: url)
        guard LiveHTTP.isSuccess(response) else {
            throw LiveError.httpFailed
        }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? ""
        let parsed = M3UPlaylistParser.parsePlaylist(text)
        if parsed.isEmpty {
            throw LiveError.emptyPlaylist
        }
        return parsed
    }
}
