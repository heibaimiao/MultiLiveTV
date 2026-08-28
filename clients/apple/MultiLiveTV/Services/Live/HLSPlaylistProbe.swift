import Foundation

enum HLSPlaylistProbe {
    enum Decision: Equatable {
        case playable
        case flv
        case mpegts
        case retry
        case reject
    }

    static let maxPendingAttempts = 5
    static let probeByteLimit = 2048
    static var startTimeout: TimeInterval { NetworkConfig.requestTimeout }

    static func evaluate(
        statusCode: Int,
        contentType: String?,
        body: String,
        pendingAttempt: Int
    ) -> Decision {
        evaluate(
            statusCode: statusCode,
            contentType: contentType,
            body: Data(body.utf8),
            pendingAttempt: pendingAttempt
        )
    }

    static func evaluate(
        statusCode: Int,
        contentType: String?,
        body: Data,
        pendingAttempt: Int
    ) -> Decision {
        if statusCode == 202 {
            return pendingAttempt >= maxPendingAttempts - 1 ? .reject : .retry
        }
        guard (200...299).contains(statusCode) else { return .reject }
        let type = contentType?.lowercased() ?? ""
        if looksLikeFLV(body, contentType: type) {
            return .flv
        }
        if looksLikeMPEGTS(body, contentType: type) {
            return .mpegts
        }
        if looksLikeMP4(body, contentType: type) {
            return .playable
        }
        var text = String(data: body, encoding: .utf8) ?? ""
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        let isHLS = type.contains("mpegurl") || text.uppercased().hasPrefix("#EXTM3U")
        if isHLS {
            if looksLikeDisguisedMediaPlaylist(text) {
                return .mpegts
            }
            return .playable
        }
        return .reject
    }

    static func looksLikeFLV(_ body: Data, contentType: String) -> Bool {
        if contentType.contains("flv") {
            return true
        }
        guard body.count >= 3 else { return false }
        return body[0] == 0x46 && body[1] == 0x4C && body[2] == 0x56
    }

    static func looksLikeMPEGTS(_ body: Data, contentType: String) -> Bool {
        if contentType.contains("mp2t") || contentType.contains("mpegts") {
            return true
        }
        let packetSize = 188
        guard body.count >= packetSize else { return false }
        let searchLimit = min(body.count, packetSize)
        for offset in 0..<searchLimit where body[offset] == 0x47 {
            let next = offset + packetSize
            if next < body.count {
                return body[next] == 0x47
            }
            return offset == 0
        }
        return false
    }

    static func looksLikeMP4(_ body: Data, contentType: String) -> Bool {
        if contentType.contains("mp4") || contentType.contains("iso.segment") {
            return true
        }
        guard body.count >= 8 else { return false }
        return body[4] == 0x66 && body[5] == 0x74 && body[6] == 0x79 && body[7] == 0x70
    }

    static func looksLikeDisguisedMediaPlaylist(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains(".jpeg")
            || lower.contains(".jpg")
            || lower.contains(".png")
            || lower.contains(".gif")
            || lower.contains(".webp")
    }

    static func shouldFailOverForStartTimeout(
        elapsed: TimeInterval,
        isReadyToPlay: Bool,
        timeout: TimeInterval = startTimeout
    ) -> Bool {
        elapsed >= timeout && !isReadyToPlay
    }
}
