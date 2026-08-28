import CryptoKit
import Foundation

enum DownloadStatus: String, Codable, Equatable {
    case queued
    case resolving
    case downloading
    case completed
    case failed
    case paused
    case evicted
}

struct DownloadRecord: Codable, Equatable, Identifiable {
    let id: String
    var sourceId: Int
    var vodId: String
    var vodName: String
    var posterURL: String
    var playSourceKey: String
    var playSourceName: String
    var episodeName: String
    var originalURL: String
    var resolvedURL: String?
    var status: DownloadStatus
    var bytesWritten: Int64
    var bytesExpected: Int64
    var fraction: Double
    var mediaKind: DownloadMediaKind?
    var localPath: String?
    var assetTitle: String?
    var errorMessage: String?

    static func stableID(
        sourceId: Int,
        vodId: String,
        playSourceKey: String,
        episodeURL: String
    ) -> String {
        let raw = "\(sourceId)|\(vodId)|\(playSourceKey)|\(episodeURL)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    var statusLabel: String {
        switch status {
        case .queued:
            return "等待中"
        case .resolving:
            return "解析地址…"
        case .downloading:
            let percent = Int((fraction * 100).rounded())
            return percent > 0 ? "下载中 \(percent)%" : "下载中"
        case .completed:
            return "已下载"
        case .failed:
            return errorMessage ?? "下载失败"
        case .paused:
            return "已暂停"
        case .evicted:
            return "已被系统清理"
        }
    }

    var allowsNewDownload: Bool {
        switch status {
        case .failed, .evicted, .paused:
            return true
        case .queued, .resolving, .downloading, .completed:
            return false
        }
    }

    mutating func prepareForRetry() {
        status = .queued
        resolvedURL = nil
        errorMessage = nil
        bytesWritten = 0
        bytesExpected = 0
        fraction = 0
        mediaKind = nil
        localPath = nil
        assetTitle = nil
    }
}

struct DownloadRequest {
    let sourceId: Int
    let vodId: String
    let vodName: String
    let posterURL: String
    let playSourceKey: String
    let playSourceName: String
    let episodeName: String
    let originalURL: String

    var id: String {
        DownloadRecord.stableID(
            sourceId: sourceId,
            vodId: vodId,
            playSourceKey: playSourceKey,
            episodeURL: originalURL
        )
    }

    func makeRecord() -> DownloadRecord {
        DownloadRecord(
            id: id,
            sourceId: sourceId,
            vodId: vodId,
            vodName: vodName,
            posterURL: posterURL,
            playSourceKey: playSourceKey,
            playSourceName: playSourceName,
            episodeName: episodeName,
            originalURL: originalURL,
            resolvedURL: nil,
            status: .queued,
            bytesWritten: 0,
            bytesExpected: 0,
            fraction: 0,
            mediaKind: nil,
            localPath: nil,
            assetTitle: nil,
            errorMessage: nil
        )
    }
}
