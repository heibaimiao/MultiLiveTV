import Foundation

enum NetworkConfig {
    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    static let requestTimeout: TimeInterval = 15
}

enum RequestFailure {
    static func userFacingMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            return message(for: urlError.code)
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return message(for: URLError.Code(rawValue: nsError.code))
        }
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return "加载失败，请稍后重试"
    }

    private static func message(for code: URLError.Code) -> String {
        switch code {
        case .timedOut:
            return "请求超时，请检查网络后重试"
        case .notConnectedToInternet, .dataNotAllowed:
            return "网络不可用，请检查网络后重试"
        case .cannotFindHost, .dnsLookupFailed:
            return "无法连接服务器，请稍后重试"
        case .cannotConnectToHost, .networkConnectionLost, .cannotLoadFromNetwork:
            return "连接失败，请稍后重试"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired:
            return "安全连接失败，请稍后重试"
        case .badServerResponse, .zeroByteResource, .cannotParseResponse, .cannotDecodeContentData,
             .cannotDecodeRawData:
            return "服务器响应异常，请稍后重试"
        case .badURL, .unsupportedURL:
            return "请求地址无效"
        default:
            return "加载失败，请稍后重试"
        }
    }
}

enum RemoteMediaURL {
    static func parse(_ string: String) -> URL? {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("//") {
            trimmed = "https:" + trimmed
        }
        guard let url = makeURL(trimmed), isUsable(url) else { return nil }
        return url
    }

    private static func makeURL(_ string: String) -> URL? {
        if let url = URL(string: string) { return url }
        return string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
    }

    private static func isUsable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return url.host?.isEmpty == false
    }
}
