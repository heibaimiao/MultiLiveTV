import Foundation

enum AppDeepLink {
    static let scheme = "multilivetv"
    static let host = "vod"

    struct VodTarget: Equatable {
        let sourceId: Int
        let vodId: String
    }

    static func vodURL(sourceId: Int, vodId: String) -> URL? {
        let trimmed = vodId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        return URL(string: "\(scheme)://\(host)/\(sourceId)/\(encoded)")
    }

    static func parse(_ url: URL) -> VodTarget? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard url.host?.lowercased() == host else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, let sourceId = Int(parts[0]) else { return nil }
        let raw = parts.dropFirst().joined(separator: "/")
        let vodId = raw.removingPercentEncoding ?? raw
        guard !vodId.isEmpty else { return nil }
        return VodTarget(sourceId: sourceId, vodId: vodId)
    }
}
