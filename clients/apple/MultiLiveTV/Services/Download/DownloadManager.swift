import Foundation

@MainActor
protocol PlayURLParsing: AnyObject {
    func parsePlay(sourceId: Int, url: String) async throws -> ParseResponse
    func source(for id: Int) -> Source?
}

enum DownloadUserMessage {
    static func enqueue(_ outcome: DownloadEnqueueOutcome) -> String? {
        switch outcome {
        case .queued, .resetToQueued, .alreadyInQueue:
            return nil
        case .alreadyCompleted:
            return "已下载"
        case .insufficientDisk:
            return "存储空间不足，请清理后再下载"
        }
    }
}

@MainActor
final class DownloadManager: ObservableObject {
    static weak var backgroundSessionOwner: DownloadManager?

    @Published private(set) var records: [DownloadRecord] = []

    private let store: DownloadStore
    private let parser: any PlayURLParsing
    private let hlsEngine: any DownloadEngine
    private let fileEngine: any DownloadEngine
    private var pauseRequested: Set<String> = []
    private var deleteRequested: Set<String> = []
    private var workerRunning = false
    private var lastProgressWrite: [String: Date] = [:]

    init(
        parser: any PlayURLParsing,
        store: DownloadStore? = nil,
        hlsEngine: (any DownloadEngine)? = nil,
        fileEngine: (any DownloadEngine)? = nil
    ) {
        self.parser = parser
        let resolvedStore: DownloadStore
        if let store {
            resolvedStore = store
        } else {
            let root = (try? DownloadStore.defaultRoot())
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("downloads", isDirectory: true)
            resolvedStore = DownloadStore(rootURL: root)
        }
        self.store = resolvedStore

        let hls: any DownloadEngine
        if let hlsEngine {
            hls = hlsEngine
        } else {
            #if os(iOS)
            hls = HLSDownloadEngine()
            #else
            hls = HLSPlaylistDownloadEngine()
            #endif
        }
        let file = fileEngine ?? FileDownloadEngine { resolvedStore.filesDirectory(for: $0) }
        self.hlsEngine = hls
        self.fileEngine = file

        hls.onProgress = { [weak self] id, fraction, written, expected in
            Task { @MainActor in
                self?.handleProgress(id: id, fraction: fraction, written: written, expected: expected)
            }
        }
        file.onProgress = { [weak self] id, fraction, written, expected in
            Task { @MainActor in
                self?.handleProgress(id: id, fraction: fraction, written: written, expected: expected)
            }
        }

        DownloadManager.backgroundSessionOwner = self
        records = resolvedStore.reconcileEvicted(resolvedStore.load())
        persist()
    }

    func restore() async {
        let inflight = await hlsEngine.adoptExistingTasks().union(await fileEngine.adoptExistingTasks())

        for index in records.indices {
            let status = records[index].status
            if status == .resolving {
                records[index].status = .queued
            } else if status == .downloading && !inflight.contains(records[index].id) {
                records[index].status = .queued
            }
        }
        persist()

        for id in inflight {
            guard let record = records.first(where: { $0.id == id }) else {
                hlsEngine.cancel(id: id)
                fileEngine.cancel(id: id)
                continue
            }
            await finishRestored(record)
        }

        kickWorker()
    }

    func handleBackgroundEvents(identifier: String, completionHandler: @escaping () -> Void) {
        if identifier == DownloadSessionID.hls {
            hlsEngine.backgroundCompletionHandler = completionHandler
        } else if identifier == DownloadSessionID.file {
            fileEngine.backgroundCompletionHandler = completionHandler
        } else {
            completionHandler()
        }
    }

    func enqueue(_ request: DownloadRequest) -> DownloadEnqueueOutcome {
        let existing = records.first(where: { $0.id == request.id })
        let fileExists = existing?.localPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
        let outcome = DownloadEnqueuePolicy.outcome(
            existing: existing,
            fileExists: fileExists,
            freeDiskBytes: freeDiskBytes()
        )
        switch outcome {
        case .queued:
            records.append(request.makeRecord())
            persist()
            kickWorker()
        case .resetToQueued:
            update(request.id) { $0.prepareForRetry() }
            persist()
            kickWorker()
        case .alreadyCompleted, .insufficientDisk, .alreadyInQueue:
            break
        }
        return outcome
    }

    func enqueueEpisode(vod: VodItem, playSource: PlaySource, episode: Episode) -> DownloadEnqueueOutcome {
        enqueue(
            DownloadRequest(
                sourceId: playSource.sourceId ?? vod.resolvedSourceId,
                vodId: vod.vodId,
                vodName: vod.vodName,
                posterURL: vod.vodPic,
                playSourceKey: playSource.key,
                playSourceName: playSource.name,
                episodeName: episode.name,
                originalURL: episode.url
            )
        )
    }

    func enqueueLine(vod: VodItem, playSource: PlaySource) -> DownloadEnqueueOutcome {
        var queuedAny = false
        var last: DownloadEnqueueOutcome = .alreadyCompleted
        for episode in playSource.episodes {
            let outcome = enqueueEpisode(vod: vod, playSource: playSource, episode: episode)
            if outcome == .insufficientDisk {
                return .insufficientDisk
            }
            if outcome == .queued || outcome == .resetToQueued {
                queuedAny = true
            }
            last = outcome
        }
        return queuedAny ? .queued : last
    }

    func pause(id: String) {
        pauseRequested.insert(id)
        hlsEngine.cancel(id: id)
        fileEngine.cancel(id: id)
        if let record = records.first(where: { $0.id == id }),
           record.status == .queued || record.status == .resolving {
            pauseRequested.remove(id)
            update(id) { $0.status = .paused }
            persist()
        }
    }

    func resume(id: String) {
        pauseRequested.remove(id)
        update(id) { record in
            if record.status == .paused || record.status == .failed || record.status == .evicted {
                record.prepareForRetry()
            }
        }
        persist()
        kickWorker()
    }

    func delete(id: String) {
        deleteRequested.insert(id)
        pauseRequested.remove(id)
        hlsEngine.cancel(id: id)
        fileEngine.cancel(id: id)
        if let path = records.first(where: { $0.id == id })?.localPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        try? store.delete(id: id)
        records.removeAll { $0.id == id }
        persist()
    }

    func record(sourceId: Int, vodId: String, playSourceKey: String, episodeURL: String) -> DownloadRecord? {
        let id = DownloadRecord.stableID(
            sourceId: sourceId,
            vodId: vodId,
            playSourceKey: playSourceKey,
            episodeURL: episodeURL
        )
        return records.first { $0.id == id }
    }

    func playbackURL(sourceId: Int, episodeURL: String) -> URL? {
        guard let record = records.first(where: {
            $0.sourceId == sourceId && $0.originalURL == episodeURL && $0.status == .completed
        }) else {
            return nil
        }
        if let path = record.localPath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        markEvicted(id: record.id)
        return nil
    }

    func hasEvicted(sourceId: Int, episodeURL: String) -> Bool {
        records.contains {
            $0.sourceId == sourceId && $0.originalURL == episodeURL && $0.status == .evicted
        }
    }

    func markEvicted(id: String) {
        update(id) {
            $0.status = .evicted
            $0.errorMessage = "已被系统清理"
        }
        persist()
    }

    func groupedRecords() -> [DownloadGroup] {
        Dictionary(grouping: records, by: \.vodId)
            .map { key, items in
                DownloadGroup(
                    vodId: key,
                    vodName: items.first?.vodName ?? "",
                    posterURL: items.first?.posterURL ?? "",
                    items: items.sorted {
                        $0.episodeName.localizedStandardCompare($1.episodeName) == .orderedAscending
                    }
                )
            }
            .sorted { $0.vodName.localizedStandardCompare($1.vodName) == .orderedAscending }
    }

    // MARK: - Worker

    private func kickWorker() {
        guard !workerRunning else { return }
        workerRunning = true
        Task {
            await processQueue()
            workerRunning = false
            if records.contains(where: { $0.status == .queued }) {
                kickWorker()
            }
        }
    }

    private func processQueue() async {
        while let record = records.first(where: { $0.status == .queued }) {
            await process(record)
        }
    }

    private func process(_ record: DownloadRecord) async {
        let id = record.id
        update(id) {
            $0.status = .resolving
            $0.errorMessage = nil
        }
        persist()

        do {
            let parsed = try await parser.parsePlay(sourceId: record.sourceId, url: record.originalURL)
            switch DownloadEnqueuePolicy.actionAfterResolve(
                deleteRequested: deleteRequested.remove(id) != nil,
                pauseRequested: pauseRequested.remove(id) != nil
            ) {
            case .discard:
                return
            case .pause:
                update(id) { $0.status = .paused }
                persist()
                return
            case .proceed:
                break
            }

            let kind = DownloadMediaClassifier.classify(parsed.url)
            guard kind != .unsupported else {
                fail(id, message: "当前线路无法下载，请换 m3u8 线路")
                return
            }
            guard let assetURL = Self.makeURL(from: parsed.url) else {
                fail(id, message: "无效播放地址")
                return
            }
            guard let source = parser.source(for: record.sourceId) else {
                fail(id, message: "资源站不存在")
                return
            }

            let headers = PlaybackSupport.httpHeaders(for: source, playbackURL: assetURL)
            let title = "\(record.vodName) \(record.episodeName)"
            update(id) {
                $0.resolvedURL = parsed.url
                $0.mediaKind = kind
                $0.status = .downloading
                $0.assetTitle = title
            }
            persist()

            let destination = store.filesDirectory(for: id)
            let localURL: URL
            switch kind {
            case .hls:
                localURL = try await hlsEngine.start(
                    id: id,
                    assetURL: assetURL,
                    headers: headers,
                    title: title,
                    destinationDirectory: destination
                )
            case .progressive:
                localURL = try await fileEngine.start(
                    id: id,
                    assetURL: assetURL,
                    headers: headers,
                    title: title,
                    destinationDirectory: destination
                )
            case .unsupported:
                return
            }

            let deleted = deleteRequested.remove(id) != nil || !records.contains(where: { $0.id == id })
            let paused = pauseRequested.remove(id) != nil
            switch DownloadEnqueuePolicy.actionAfterEngineSuccess(deleteRequested: deleted, pauseRequested: paused) {
            case .discard:
                try? FileManager.default.removeItem(at: localURL)
            case .complete:
                complete(id, localURL: localURL)
            }
        } catch is CancellationError {
            handleCancel(id)
        } catch {
            switch DownloadEnqueuePolicy.actionAfterResolve(
                deleteRequested: deleteRequested.remove(id) != nil,
                pauseRequested: pauseRequested.remove(id) != nil
            ) {
            case .discard:
                return
            case .pause:
                update(id) { $0.status = .paused }
                persist()
                return
            case .proceed:
                fail(
                    id,
                    message: PlaybackSupport.userFacingError(
                        for: parsedURL(for: id) ?? record.originalURL,
                        underlying: error.localizedDescription
                    )
                )
            }
        }
    }

    private func finishRestored(_ record: DownloadRecord) async {
        do {
            let localURL: URL
            if hlsEngine.attachedTaskIDs().contains(record.id) {
                localURL = try await hlsEngine.waitForTask(id: record.id)
            } else {
                localURL = try await fileEngine.waitForTask(id: record.id)
            }
            let deleted = deleteRequested.remove(record.id) != nil
            let paused = pauseRequested.remove(record.id) != nil
            switch DownloadEnqueuePolicy.actionAfterEngineSuccess(deleteRequested: deleted, pauseRequested: paused) {
            case .discard:
                return
            case .complete:
                complete(record.id, localURL: localURL)
            }
        } catch is CancellationError {
            handleCancel(record.id)
        } catch {
            switch DownloadEnqueuePolicy.actionAfterResolve(
                deleteRequested: deleteRequested.remove(record.id) != nil,
                pauseRequested: pauseRequested.remove(record.id) != nil
            ) {
            case .discard:
                return
            case .pause:
                update(record.id) { $0.status = .paused }
                persist()
                return
            case .proceed:
                fail(record.id, message: error.localizedDescription)
            }
        }
    }

    private func handleCancel(_ id: String) {
        if deleteRequested.remove(id) != nil { return }
        pauseRequested.remove(id)
        if records.contains(where: { $0.id == id }) {
            update(id) { $0.status = .paused }
            persist()
        }
    }

    private func complete(_ id: String, localURL: URL) {
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            fail(id, message: "下载完成但文件不存在")
            return
        }
        store.excludeFromBackup(localURL)
        update(id) {
            $0.status = .completed
            $0.localPath = localURL.path
            $0.fraction = 1
            $0.errorMessage = nil
        }
        persist()
    }

    private func fail(_ id: String, message: String) {
        update(id) {
            $0.status = .failed
            $0.errorMessage = message
        }
        persist()
    }

    private func handleProgress(id: String, fraction: Double, written: Int64, expected: Int64) {
        let now = Date()
        if let last = lastProgressWrite[id], now.timeIntervalSince(last) < 0.5, fraction < 1 {
            return
        }
        lastProgressWrite[id] = now
        update(id) {
            $0.fraction = fraction
            $0.bytesWritten = written
            $0.bytesExpected = expected
        }
    }

    private func update(_ id: String, _ body: (inout DownloadRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        body(&records[index])
    }

    private func persist() {
        try? store.save(records)
    }

    private func parsedURL(for id: String) -> String? {
        records.first(where: { $0.id == id })?.resolvedURL
    }

    private func freeDiskBytes() -> Int64 {
        try? FileManager.default.createDirectory(at: store.rootURL, withIntermediateDirectories: true)
        #if os(iOS)
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        #else
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityKey]
        #endif
        guard let values = try? store.rootURL.resourceValues(forKeys: keys) else {
            return DownloadEnqueuePolicy.minimumFreeBytes
        }
        #if os(iOS)
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
            return Int64(important)
        }
        #endif
        if let capacity = values.volumeAvailableCapacity, capacity > 0 {
            return Int64(capacity)
        }
        return DownloadEnqueuePolicy.minimumFreeBytes
    }

    private static func makeURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed) { return url }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
        return encoded.flatMap { URL(string: $0) }
    }
}

struct DownloadGroup: Identifiable {
    var id: String { vodId }
    let vodId: String
    let vodName: String
    let posterURL: String
    let items: [DownloadRecord]
}
