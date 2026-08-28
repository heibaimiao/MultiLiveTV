import Foundation

final class HLSPlaylistDownloadEngine: DownloadEngine {
    var onProgress: ((String, Double, Int64, Int64) -> Void)?
    var backgroundCompletionHandler: (() -> Void)?

    private var cancelledIDs: Set<String> = []
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func start(
        id: String,
        assetURL: URL,
        headers: [String: String],
        title: String,
        destinationDirectory: URL
    ) async throws -> URL {
        _ = title
        cancelledIDs.remove(id)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let playlistData = try await fetch(assetURL, headers: headers, id: id)
        guard let playlistText = String(data: playlistData, encoding: .utf8) else {
            throw DownloadEngineError.missingLocation
        }

        let mediaURL: URL
        let mediaText: String
        if HLSPlaylistLocalizer.isMasterPlaylist(playlistText) {
            guard let variant = HLSPlaylistLocalizer.pickVariantURL(
                playlist: playlistText,
                base: assetURL,
                maxBandwidth: 4_000_000
            ) else {
                throw DownloadEngineError.missingLocation
            }
            mediaURL = variant
            let variantData = try await fetch(variant, headers: headers, id: id)
            guard let text = String(data: variantData, encoding: .utf8) else {
                throw DownloadEngineError.missingLocation
            }
            mediaText = text
        } else {
            mediaURL = assetURL
            mediaText = playlistText
        }

        let plan = HLSPlaylistLocalizer.plan(mediaPlaylist: mediaText, base: mediaURL)
        let total = max(plan.downloads.count, 1)
        for (index, item) in plan.downloads.enumerated() {
            try Task.checkCancellation()
            if cancelledIDs.contains(id) { throw CancellationError() }
            let data = try await fetch(item.remote, headers: headers, id: id)
            try data.write(to: destinationDirectory.appendingPathComponent(item.localName), options: .atomic)
            let fraction = Double(index + 1) / Double(total)
            onProgress?(id, fraction, Int64(index + 1), Int64(total))
        }

        let localPlaylist = destinationDirectory.appendingPathComponent("index.m3u8")
        try plan.playlist.write(to: localPlaylist, atomically: true, encoding: .utf8)
        onProgress?(id, 1, Int64(total), Int64(total))
        return localPlaylist
    }

    func cancel(id: String) {
        cancelledIDs.insert(id)
    }

    func adoptExistingTasks() async -> Set<String> {
        []
    }

    func waitForTask(id: String) async throws -> URL {
        _ = id
        throw DownloadEngineError.cannotCreateTask
    }

    func attachedTaskIDs() -> Set<String> {
        []
    }

    private func fetch(_ url: URL, headers: [String: String], id: String) async throws -> Data {
        if cancelledIDs.contains(id) { throw CancellationError() }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: request)
        if cancelledIDs.contains(id) { throw CancellationError() }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DownloadEngineError.httpStatus(http.statusCode)
        }
        return data
    }
}
