import Foundation

enum HLSPlaylistProbe {
    enum Decision: Equatable {
        case playable
        case flv
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
        if type.contains("mpegurl") {
            return .playable
        }
        if looksLikeFLV(body, contentType: type) {
            return .flv
        }
        guard var text = String(data: body, encoding: .utf8) else {
            return .reject
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        if text.uppercased().hasPrefix("#EXTM3U") {
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

    static func shouldFailOverForStartTimeout(
        elapsed: TimeInterval,
        isReadyToPlay: Bool,
        timeout: TimeInterval = startTimeout
    ) -> Bool {
        elapsed >= timeout && !isReadyToPlay
    }
}
