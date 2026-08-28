import Foundation

enum DownloadMediaKind: String, Codable, Equatable {
    case hls
    case progressive
    case unsupported
}

enum DownloadMediaClassifier {
    static func classify(_ url: String) -> DownloadMediaKind {
        let lower = url.lowercased()
        if lower.contains(".m3u8") {
            return .hls
        }
        if lower.contains(".mp4") || lower.contains(".mov") {
            return .progressive
        }
        return .unsupported
    }
}
