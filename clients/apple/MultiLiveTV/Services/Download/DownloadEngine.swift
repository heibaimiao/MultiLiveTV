import Foundation

enum DownloadEngineError: LocalizedError {
    case cannotCreateTask
    case missingLocation
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .cannotCreateTask:
            return "无法创建下载任务"
        case .missingLocation:
            return "下载完成但未找到本地文件"
        case .httpStatus(let code):
            return "下载失败（HTTP \(code)）"
        }
    }
}

protocol DownloadEngine: AnyObject {
    var onProgress: ((String, Double, Int64, Int64) -> Void)? { get set }
    var backgroundCompletionHandler: (() -> Void)? { get set }

    func start(
        id: String,
        assetURL: URL,
        headers: [String: String],
        title: String,
        destinationDirectory: URL
    ) async throws -> URL

    func cancel(id: String)
    func adoptExistingTasks() async -> Set<String>
    func waitForTask(id: String) async throws -> URL
    func attachedTaskIDs() -> Set<String>
}

enum DownloadSessionID {
    static let hls = "com.heibaimiao.multilivetv.asset-downloads"
    static let file = "com.heibaimiao.multilivetv.file-downloads"
}
