import Foundation

enum RemoteImagePolicy {
    static let maxAttempts = 3
    static let maxConcurrent = 4

    static func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(NetworkConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = NetworkConfig.requestTimeout
        request.cachePolicy = .returnCacheDataElseLoad
        return request
    }

    static func shouldRetry(attempt: Int, statusCode: Int?, error: Error?) -> Bool {
        guard attempt < maxAttempts else { return false }
        if let statusCode {
            return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
        }
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost,
             .secureConnectionFailed, .cannotLoadFromNetwork, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }
}

actor RemoteImageLoader {
    static let shared = RemoteImageLoader()

    private let fetch: @Sendable (URL) async throws -> Data
    private let cache = NSCache<NSURL, NSData>()
    private var inflight: [URL: Task<Data, Error>] = [:]

    init(fetch: (@Sendable (URL) async throws -> Data)? = nil) {
        cache.countLimit = 300
        cache.totalCostLimit = 40 * 1024 * 1024
        if let fetch {
            self.fetch = fetch
        } else {
            let session = Self.makeSession()
            self.fetch = { url in
                try await Self.download(url: url, session: session)
            }
        }
    }

    func data(for url: URL) async throws -> Data {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached as Data
        }

        let task: Task<Data, Error>
        if let existing = inflight[url] {
            task = existing
        } else {
            let fetch = self.fetch
            task = Task<Data, Error> {
                try await fetch(url)
            }
            inflight[url] = task
        }

        do {
            let data = try await task.value
            cache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
            inflight[url] = nil
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            inflight[url] = nil
            throw error
        }
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = NetworkConfig.requestTimeout
        config.timeoutIntervalForResource = NetworkConfig.requestTimeout * 2
        config.httpMaximumConnectionsPerHost = RemoteImagePolicy.maxConcurrent
        config.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 80 * 1024 * 1024
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }

    private static func download(url: URL, session: URLSession) async throws -> Data {
        var lastError: Error = URLError(.cannotLoadFromNetwork)
        for attempt in 1...RemoteImagePolicy.maxAttempts {
            await AsyncGate.shared.enter()
            do {
                let data = try await fetchOnce(url: url, session: session)
                await AsyncGate.shared.leave()
                return data
            } catch {
                await AsyncGate.shared.leave()
                lastError = error
                let status = (error as? ImageHTTPError)?.statusCode
                let underlying = (error as? ImageHTTPError)?.underlying ?? error
                if RemoteImagePolicy.shouldRetry(attempt: attempt, statusCode: status, error: underlying) {
                    let delay = UInt64(attempt) * 200_000_000
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    private static func fetchOnce(url: URL, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: RemoteImagePolicy.makeRequest(url: url))
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw ImageHTTPError(statusCode: http.statusCode, underlying: URLError(.badServerResponse))
        }
        guard !data.isEmpty else {
            throw URLError(.zeroByteResource)
        }
        return data
    }
}

private struct ImageHTTPError: Error {
    let statusCode: Int
    let underlying: Error
}

actor AsyncGate {
    static let shared = AsyncGate(limit: RemoteImagePolicy.maxConcurrent)

    private let limit: Int
    private var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    func enter() async {
        if count < limit {
            count += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func leave() {
        if waiters.isEmpty {
            if count > 0 { count -= 1 }
            return
        }
        waiters.removeFirst().resume()
    }
}
