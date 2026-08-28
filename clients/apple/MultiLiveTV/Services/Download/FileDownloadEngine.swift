import Foundation

final class FileDownloadEngine: NSObject, DownloadEngine, URLSessionDownloadDelegate {
    var onProgress: ((String, Double, Int64, Int64) -> Void)?
    var backgroundCompletionHandler: (() -> Void)?

    private var session: URLSession!
    private let destinationProvider: (String) -> URL
    private var continuations: [Int: CheckedContinuation<URL, Error>] = [:]
    private var idByTask: [Int: String] = [:]
    private var taskByID: [String: URLSessionDownloadTask] = [:]
    private var destinations: [Int: URL] = [:]
    private var locations: [Int: URL] = [:]
    private var httpErrors: [Int: Int] = [:]

    init(destinationProvider: @escaping (String) -> URL) {
        self.destinationProvider = destinationProvider
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: DownloadSessionID.file)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.networkServiceType = .video
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }

    func start(
        id: String,
        assetURL: URL,
        headers: [String: String],
        title: String,
        destinationDirectory: URL
    ) async throws -> URL {
        _ = title
        cancel(id: id)

        var request = URLRequest(url: assetURL)
        request.timeoutInterval = 60
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let task = session.downloadTask(with: request)
        task.taskDescription = id

        return try await withCheckedThrowingContinuation { continuation in
            continuations[task.taskIdentifier] = continuation
            idByTask[task.taskIdentifier] = id
            taskByID[id] = task
            destinations[task.taskIdentifier] = destinationDirectory
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
            guard let id = task.taskDescription, let downloadTask = task as? URLSessionDownloadTask else {
                continue
            }
            taskByID[id] = downloadTask
            idByTask[downloadTask.taskIdentifier] = id
            destinations[downloadTask.taskIdentifier] = destinationProvider(id)
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

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            httpErrors[downloadTask.taskIdentifier] = http.statusCode
            return
        }

        let destDir = destinations[downloadTask.taskIdentifier]
            ?? idByTask[downloadTask.taskIdentifier].map(destinationProvider)
        guard let destDir else { return }

        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            let ext = downloadTask.originalRequest?.url?.pathExtension.isEmpty == false
                ? downloadTask.originalRequest!.url!.pathExtension
                : "mp4"
            let file = destDir.appendingPathComponent("video.\(ext)")
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            try FileManager.default.moveItem(at: location, to: file)
            locations[downloadTask.taskIdentifier] = file
        } catch {
            httpErrors[downloadTask.taskIdentifier] = -1
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = idByTask[downloadTask.taskIdentifier] else { return }
        let fraction: Double
        if totalBytesExpectedToWrite > 0 {
            fraction = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        } else {
            fraction = 0
        }
        onProgress?(id, fraction, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskID = task.taskIdentifier
        let continuation = continuations.removeValue(forKey: taskID)
        let id = idByTask.removeValue(forKey: taskID)
        if let id {
            taskByID.removeValue(forKey: id)
        }
        destinations.removeValue(forKey: taskID)

        if let error {
            continuation?.resume(throwing: Self.mapCancel(error))
            return
        }
        if let code = httpErrors.removeValue(forKey: taskID) {
            locations.removeValue(forKey: taskID)
            if code > 0 {
                continuation?.resume(throwing: DownloadEngineError.httpStatus(code))
            } else {
                continuation?.resume(throwing: DownloadEngineError.missingLocation)
            }
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
}
