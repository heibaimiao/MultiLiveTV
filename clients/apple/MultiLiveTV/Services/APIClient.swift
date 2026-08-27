import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case badStatus(Int)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "请先登录"
        case .badStatus(let code): return "请求失败 (\(code))"
        case .decodeFailed: return "数据解析失败"
        }
    }
}

@MainActor
final class APIClient: ObservableObject {
    @Published var accessToken: String?
    @Published var refreshToken: String?
    @Published var isLoggedIn = false

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    init() {
        accessToken = KeychainStore.load(key: "access_token")
        refreshToken = KeychainStore.load(key: "refresh_token")
        isLoggedIn = accessToken != nil
    }

    // MARK: - HTTP

    private func request(_ url: URL, method: String = "GET", body: Data? = nil, auth: Bool = false) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if auth, let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(0) }

        if http.statusCode == 401, auth, let rt = refreshToken {
            try await refreshSession(refreshToken: rt)
            return try await request(url, method: method, body: body, auth: auth)
        }

        guard (200...299).contains(http.statusCode) else {
            throw APIError.badStatus(http.statusCode)
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], auth: Bool = false) async throws -> T {
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        let data = try await request(components.url!, auth: auth)
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, payload: some Encodable, auth: Bool = false) async throws -> T {
        let url = APIConfig.baseURL.appendingPathComponent(path)
        let body = try JSONEncoder().encode(payload)
        let data = try await request(url, method: "POST", body: body, auth: auth)
        return try decoder.decode(T.self, from: data)
    }

    private func put<T: Decodable>(_ path: String, payload: some Encodable, auth: Bool = false) async throws -> T {
        let url = APIConfig.baseURL.appendingPathComponent(path)
        let body = try JSONEncoder().encode(payload)
        let data = try await request(url, method: "PUT", body: body, auth: auth)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - VOD

    func fetchTypes(sourceId: Int? = nil) async throws -> TypesResponse {
        var query: [URLQueryItem] = []
        if let sourceId { query.append(URLQueryItem(name: "sourceId", value: String(sourceId))) }
        return try await get("vod/types", query: query)
    }

    func fetchList(page: Int, typeId: Int? = nil, sourceId: Int? = nil) async throws -> ListResponse {
        var query = [URLQueryItem(name: "pg", value: String(page))]
        if let typeId { query.append(URLQueryItem(name: "t", value: String(typeId))) }
        if let sourceId { query.append(URLQueryItem(name: "sourceId", value: String(sourceId))) }
        return try await get("vod/list", query: query)
    }

    func search(_ keyword: String, page: Int = 1) async throws -> [VodItem] {
        let resp: SearchResponse = try await get("vod/search", query: [
            URLQueryItem(name: "wd", value: keyword),
            URLQueryItem(name: "pg", value: String(page)),
        ])
        return resp.list
    }

    func detail(sourceId: Int, vodId: String) async throws -> DetailResponse {
        try await get("vod/detail", query: [
            URLQueryItem(name: "sourceId", value: String(sourceId)),
            URLQueryItem(name: "ids", value: vodId),
        ])
    }

    func parsePlay(sourceId: Int, url: String) async throws -> ParseResponse {
        try await get("play/parse", query: [
            URLQueryItem(name: "sourceId", value: String(sourceId)),
            URLQueryItem(name: "url", value: url),
        ])
    }

    // MARK: - Auth

    struct LoginBody: Encodable { let email: String; let password: String }
    struct RegisterBody: Encodable { let email: String; let password: String }
    struct RefreshBody: Encodable { let refresh_token: String }

    struct AuthResponse: Decodable {
        struct User: Decodable { let id: String; let email: String }
        struct Tokens: Decodable {
            let accessToken: String
            let refreshToken: String
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
            }
        }
        let user: User?
        let tokens: Tokens?
    }

    func login(email: String, password: String) async throws {
        let resp: AuthResponse = try await post("auth/login", payload: LoginBody(email: email, password: password))
        guard let tokens = resp.tokens else { throw APIError.decodeFailed }
        storeTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
    }

    func register(email: String, password: String) async throws {
        let resp: AuthResponse = try await post("auth/register", payload: RegisterBody(email: email, password: password))
        guard let tokens = resp.tokens else { throw APIError.decodeFailed }
        storeTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
    }

    func refreshSession(refreshToken: String) async throws {
        let tokens: TokenPair = try await post("auth/refresh", payload: RefreshBody(refresh_token: refreshToken))
        storeTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        isLoggedIn = false
        KeychainStore.delete(key: "access_token")
        KeychainStore.delete(key: "refresh_token")
    }

    private func storeTokens(access: String, refresh: String) {
        accessToken = access
        refreshToken = refresh
        isLoggedIn = true
        KeychainStore.save(access, key: "access_token")
        KeychainStore.save(refresh, key: "refresh_token")
    }

    // MARK: - User data

    struct FavoritesResponse: Decodable { let favorites: [Favorite] }
    struct ProgressResponse: Decodable { let progress: [WatchProgress] }
    struct FavoriteBody: Encodable {
        let merge_key: String
        let vod_name: String
        let primary_source_id: Int
        let primary_vod_id: String
        let poster: String
    }
    struct ProgressBody: Encodable {
        let progress_key: String
        let position_sec: Double
        let duration_sec: Double
    }

    func listFavorites() async throws -> [Favorite] {
        let resp: FavoritesResponse = try await get("user/favorites", auth: true)
        return resp.favorites
    }

    func addFavorite(item: VodItem) async throws -> Favorite {
        let key = HomeFeed.mergeKey(for: item)
        return try await post("user/favorites", payload: FavoriteBody(
            merge_key: key,
            vod_name: item.vodName,
            primary_source_id: item.resolvedSourceId,
            primary_vod_id: item.vodId,
            poster: item.vodPic
        ), auth: true)
    }

    func saveProgress(key: String, position: Double, duration: Double) async throws -> WatchProgress {
        try await put("user/progress", payload: ProgressBody(
            progress_key: key,
            position_sec: position,
            duration_sec: duration
        ), auth: true)
    }
}
