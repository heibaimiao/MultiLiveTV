import Foundation

struct SourceRuntimeStatus: Hashable {
    var healthy: Bool
    var lastSuccess: Date?
    var errorCount: Int

    static let initial = SourceRuntimeStatus(healthy: true, lastSuccess: nil, errorCount: 0)
}

/// Process-local health for collectable sources. Never mutates `Source.enabled`.
final class SourceHealthStore: @unchecked Sendable {
    static let shared = SourceHealthStore()
    static let failureThreshold = 5
    /// Applied to play ranking when unhealthy (negative).
    static let unhealthyPenalty = 200

    private let lock = NSLock()
    private var statusByNumericId: [Int: SourceRuntimeStatus] = [:]

    init() {}

    func status(for numericId: Int) -> SourceRuntimeStatus {
        lock.lock()
        defer { lock.unlock() }
        return statusByNumericId[numericId] ?? .initial
    }

    func recordSuccess(numericId: Int, at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        statusByNumericId[numericId] = SourceRuntimeStatus(
            healthy: true,
            lastSuccess: date,
            errorCount: 0
        )
    }

    func recordFailure(numericId: Int) {
        lock.lock()
        defer { lock.unlock() }
        var current = statusByNumericId[numericId] ?? .initial
        current.errorCount += 1
        if current.errorCount >= Self.failureThreshold {
            current.healthy = false
        }
        statusByNumericId[numericId] = current
    }

    func healthScore(for numericId: Int) -> Int {
        let s = status(for: numericId)
        if !s.healthy { return -Self.unhealthyPenalty }
        if s.errorCount == 0 { return 0 }
        return -min(s.errorCount * 20, Self.unhealthyPenalty - 20)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        statusByNumericId.removeAll()
    }
}
