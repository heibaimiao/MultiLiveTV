import AVFoundation
import CoreMedia
import Foundation

#if os(iOS)
final class HLSDownloadEngine: NSObject, DownloadEngine, AVAssetDownloadDelegate {
    var onProgress: ((String, Double, Int64, Int64) -> Void)?
    var backgroundCompletionHandler: (() -> Void)?

    private var session: AVAssetDownloadURLSession!
    private var continuations: [Int: CheckedContinuation<URL, Error>] = [:]
    private var idByTask: [Int: String] = [:]
    private var taskByID: [String: AVAssetDownloadTask] = [:]
    private var locations: [Int: URL] = [:]

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: DownloadSessionID.hls)
        configuration.networkServiceType = .video
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        session = AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: self,
            delegateQueue: .main
        )
    }

    func start(
        id: String,
        assetURL: URL,
        headers: [String: String],
        title: String,
        destinationDirectory: URL
    ) async throws -> URL {
        _ = destinationDirectory
        cancel(id: id)

        let asset = AVURLAsset(url: assetURL, options: PlaybackSupport.assetOptions(headers: headers))
        let task = makeTask(asset: asset, title: title)
        task.taskDescription = id

        return try await withCheckedThrowingContinuation { continuation in
            continuations[task.taskIdentifier] = continuation
            idByTask[task.taskIdentifier] = id
            taskByID[id] = task
            task.resume()
        }
    }

    func cancel(id: String) {
        taskByID[id]?.cancel()
    }

    func adoptExistingTasks() async -> Set<String> {
        let tasks = await session.allTasks
        var ids = Set<String>()
        for task in tasks {
            guard let id = task.taskDescription, let assetTask = task as? AVAssetDownloadTask else {
                continue
            }
            taskByID[id] = assetTask
            idByTask[assetTask.taskIdentifier] = id
            ids.insert(id)
        }
        return ids
    }

    func waitForTask(id: String) async throws -> URL {
        guard let task = taskByID[id] else {
            throw DownloadEngineError.cannotCreateTask
        }
        if continuations[task.taskIdentifier] != nil {
            throw DownloadEngineError.cannotCreateTask
        }
        return try await withCheckedThrowingContinuation { continuation in
            continuations[task.taskIdentifier] = continuation
        }
    }

    func attachedTaskIDs() -> Set<String> {
        Set(taskByID.keys)
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        locations[assetDownloadTask.taskIdentifier] = location
    }

    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        guard let id = idByTask[assetDownloadTask.taskIdentifier] else { return }
        let expected = CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
        let loaded = loadedTimeRanges.reduce(0.0) { partial, value in
            partial + CMTimeGetSeconds(value.timeRangeValue.duration)
        }
        let fraction = expected > 0 ? min(1, max(0, loaded / expected)) : 0
        onProgress?(id, fraction, 0, 0)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskID = task.taskIdentifier
        let continuation = continuations.removeValue(forKey: taskID)
        let id = idByTask.removeValue(forKey: taskID)
        if let id {
            taskByID.removeValue(forKey: id)
        }

        if let error {
            continuation?.resume(throwing: Self.mapCancel(error))
            return
        }
        if let location = locations.removeValue(forKey: taskID) {
            continuation?.resume(returning: location)
        } else {
            continuation?.resume(throwing: DownloadEngineError.missingLocation)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        backgroundCompletionHandler?()
        backgroundCompletionHandler = nil
    }

    private static func mapCancel(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
            return CancellationError()
        }
        return error
    }

    private func makeTask(asset: AVURLAsset, title: String) -> AVAssetDownloadTask {
        let configured = AVAssetDownloadConfiguration(asset: asset, title: title)
        let qualifier = AVAssetVariantQualifier(predicate: NSPredicate(format: "peakBitRate < 4000000"))
        configured.primaryContentConfiguration.variantQualifiers = [qualifier]
        return session.makeAssetDownloadTask(downloadConfiguration: configured)
    }
}
#endif
