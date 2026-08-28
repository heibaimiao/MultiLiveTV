import Foundation

enum DownloadEnqueueOutcome: Equatable {
    case queued
    case alreadyCompleted
    case resetToQueued
    case insufficientDisk
    case alreadyInQueue
}

enum DownloadFinishAction: Equatable {
    case complete
    case discard
}

enum DownloadEnqueuePolicy {
    static let minimumFreeBytes: Int64 = 1_000_000_000

    static func outcome(
        existing: DownloadRecord?,
        fileExists: Bool,
        freeDiskBytes: Int64
    ) -> DownloadEnqueueOutcome {
        if let existing {
            switch existing.status {
            case .completed:
                if fileExists {
                    return .alreadyCompleted
                }
                return requireDisk(freeDiskBytes) ?? .resetToQueued
            case .failed, .evicted, .paused:
                return requireDisk(freeDiskBytes) ?? .resetToQueued
            case .queued, .resolving, .downloading:
                return .alreadyInQueue
            }
        }
        return requireDisk(freeDiskBytes) ?? .queued
    }

    /// 本线路入队：去掉重复 id，并跳过已在队列 / 已完成的集。
    static func uniqueEpisodeIDs(_ ids: [String], existing: [String: DownloadRecord]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids {
            if seen.contains(id) { continue }
            seen.insert(id)
            if let record = existing[id] {
                switch outcome(existing: record, fileExists: record.localPath != nil, freeDiskBytes: Int64.max) {
                case .queued, .resetToQueued:
                    result.append(id)
                case .alreadyCompleted, .alreadyInQueue, .insufficientDisk:
                    continue
                }
            } else {
                result.append(id)
            }
        }
        return result
    }

    static func actionAfterEngineSuccess(deleteRequested: Bool, pauseRequested _: Bool) -> DownloadFinishAction {
        deleteRequested ? .discard : .complete
    }

    private static func requireDisk(_ freeDiskBytes: Int64) -> DownloadEnqueueOutcome? {
        freeDiskBytes < minimumFreeBytes ? .insufficientDisk : nil
    }
}
