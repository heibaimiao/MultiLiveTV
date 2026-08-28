import AVFoundation
import Foundation

enum PlaybackSupport {
    static var preferredForwardBufferDuration: TimeInterval {
        #if os(tvOS)
        30
        #else
        20
        #endif
    }

    static func isDirectMediaURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains(".m3u8")
            || lower.contains(".mp4")
            || lower.contains(".mkv")
            || lower.contains(".flv")
            || lower.contains(".mov")
    }

    static func referer(for source: Source) -> String? {
        guard let url = URL(string: source.url), let host = url.host else { return nil }
        return "\(url.scheme ?? "https")://\(host)/"
    }

    static func httpHeaders(for source: Source, playbackURL: URL) -> [String: String] {
        var headers = ["User-Agent": NetworkConfig.userAgent]
        if let referer = referer(for: source) {
            headers["Referer"] = referer
        } else if let host = playbackURL.host {
            headers["Referer"] = "\(playbackURL.scheme ?? "https")://\(host)/"
        }
        headers["Origin"] = headers["Referer"]
        return headers
    }

    static func assetOptions(headers: [String: String]) -> [String: Any] {
        var options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        if let userAgent = headers["User-Agent"] {
            options["AVURLAssetHTTPUserAgentKey"] = userAgent
        }
        return options
    }

    static func makePlayerItem(source: Source, playbackURL: URL) -> AVPlayerItem {
        makePlayerItem(playbackURL: playbackURL, headers: httpHeaders(for: source, playbackURL: playbackURL))
    }

    static func makePlayerItem(playbackURL: URL) -> AVPlayerItem {
        makePlayerItem(playbackURL: playbackURL, headers: httpHeaders(playbackURL: playbackURL))
    }

    static func makePlayerItem(playbackURL: URL, headers: [String: String]) -> AVPlayerItem {
        let asset = AVURLAsset(url: playbackURL, options: assetOptions(headers: headers))
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = preferredForwardBufferDuration
        return item
    }

    static func httpHeaders(playbackURL _: URL) -> [String: String] {
        ["User-Agent": NetworkConfig.userAgent]
    }

    static func makeLocalPlayerItem(url: URL) -> AVPlayerItem {
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        item.preferredForwardBufferDuration = preferredForwardBufferDuration
        return item
    }

    static func userFacingError(for url: String, underlying: String?) -> String {
        if ATSPolicy.isFailureMessage(underlying) {
            return "当前线路是明文 HTTP，系统禁止播放。请换 HTTPS 线路重试。"
        }
        if isDirectMediaURL(url) || RemoteMediaURL.parse(url) != nil {
            return underlying ?? "播放失败，请换线路重试"
        }
        return "当前线路为网页链接，App 无法直接播放。请换带 m3u8 的线路（如猫眼、无忧、影剧）。"
    }
}

enum ATSPolicy {
    static let conflictingKeys = [
        "NSAllowsArbitraryLoadsForMedia",
        "NSAllowsArbitraryLoadsInWebContent",
        "NSAllowsLocalNetworking",
    ]

    static func allowsInsecureHTTP(_ ats: [String: Any]) -> Bool {
        for key in conflictingKeys where ats[key] != nil {
            return false
        }
        return ats["NSAllowsArbitraryLoads"] as? Bool == true
    }

    static func isFailureMessage(_ message: String?) -> Bool {
        guard let message else { return false }
        let lower = message.lowercased()
        return lower.contains("app transport security")
            || lower.contains("requires the use of a secure connection")
    }
}

enum RequestGeneration {
    static func shouldApply(eventGeneration: Int, currentGeneration: Int) -> Bool {
        eventGeneration == currentGeneration
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if (error as? URLError)?.code == .cancelled {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
