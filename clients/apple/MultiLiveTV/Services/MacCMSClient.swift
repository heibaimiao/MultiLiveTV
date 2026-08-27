import Foundation

enum MacCMSClient {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = NetworkConfig.requestTimeout
        config.timeoutIntervalForResource = NetworkConfig.requestTimeout
        return URLSession(configuration: config)
    }()

    static func fetchTypes(source: Source) async throws -> [VodTypeRaw] {
        let data = try await fetchBody(baseURL: source.url, params: ["ac": "list", "pg": "1"])
        let response = try MacCMSJSONParser.parseList(data)
        return response.types
    }

    static func fetchList(source: Source, page: Int, typeId: Int?) async throws -> MacCMSListResponse {
        var params = ["ac": "list", "pg": String(page)]
        if let typeId { params["t"] = String(typeId) }
        let data = try await fetchBody(baseURL: source.url, params: params)
        return try MacCMSJSONParser.parseList(data)
    }

    static func fetchDetail(source: Source, ids: String) async throws -> MacCMSDetailResponse {
        let data = try await fetchBody(baseURL: source.url, params: ["ac": "detail", "ids": ids])
        return try MacCMSJSONParser.parseDetail(data)
    }

    static func search(source: Source, keyword: String, page: Int) async throws -> MacCMSListResponse {
        let data = try await fetchBody(baseURL: source.url, params: [
            "ac": "list",
            "wd": keyword,
            "pg": String(page),
        ])
        return try MacCMSJSONParser.parseList(data)
    }

    private static func fetchBody(baseURL: String, params: [String: String]) async throws -> Data {
        var base = baseURL
        if !base.hasSuffix("/") { base += "/" }

        guard var components = URLComponents(string: base) else {
            throw URLError(.badURL)
        }
        var queryItems = components.queryItems ?? []
        for (key, value) in params {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue(NetworkConfig.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
