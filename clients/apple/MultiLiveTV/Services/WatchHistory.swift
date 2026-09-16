import Foundation

struct WatchHistoryRecord: Codable, Equatable, Identifiable {
    var id: String { videoId }
    var videoId: String
    var vodId: String
    var episodeId: String
    var title: String
    var episodeTitle: String
    var episodeIndex: Int
    var cover: String
    var sourceId: Int
    var sourceName: String
    var positionMs: Int64
    var durationMs: Int64
    var progress: Double
    var lastPlayTime: Int64
    var completed: Bool

    init(
        videoId: String,
        vodId: String = "",
        episodeId: String = "",
        title: String = "",
        episodeTitle: String = "",
        episodeIndex: Int = 0,
        cover: String = "",
        sourceId: Int = 0,
        sourceName: String = "",
        positionMs: Int64 = 0,
        durationMs: Int64 = 0,
        progress: Double = 0,
        lastPlayTime: Int64 = 0,
        completed: Bool = false
    ) {
        self.videoId = videoId
        self.vodId = vodId
        self.episodeId = episodeId
        self.title = title
        self.episodeTitle = episodeTitle
        self.episodeIndex = episodeIndex
        self.cover = cover
        self.sourceId = sourceId
        self.sourceName = sourceName
        self.positionMs = positionMs
        self.durationMs = durationMs
        self.progress = progress
        self.lastPlayTime = lastPlayTime
        self.completed = completed
    }
}

enum WatchHistoryProgress {
    static let nearEndMs: Int64 = 10_000

    static func sanitizePosition(_ positionMs: Int64, durationMs: Int64) -> Int64 {
        guard durationMs > 0 else { return 0 }
        return min(max(positionMs, 0), durationMs)
    }

    static func isCompleted(_ positionMs: Int64, durationMs: Int64) -> Bool {
        guard durationMs > 0 else { return false }
        let position = sanitizePosition(positionMs, durationMs: durationMs)
        let threshold = durationMs <= nearEndMs ? durationMs : durationMs - nearEndMs
        return position >= threshold
    }

    static func progressOf(positionMs: Int64, durationMs: Int64, completed: Bool) -> Double {
        if completed { return 1 }
        guard durationMs > 0 else { return 0 }
        let ratio = Double(sanitizePosition(positionMs, durationMs: durationMs)) / Double(durationMs)
        return min(max(ratio, 0), 1)
    }

    static func normalize(_ record: WatchHistoryRecord, now: Int64? = nil) -> WatchHistoryRecord {
        var next = record
        next.videoId = record.videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        next.vodId = record.vodId.trimmingCharacters(in: .whitespacesAndNewlines)
        next.title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        next.episodeTitle = record.episodeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        next.sourceName = record.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        next.episodeIndex = max(record.episodeIndex, 0)
        next.durationMs = max(record.durationMs, 0)
        let position = sanitizePosition(record.positionMs, durationMs: next.durationMs)
        let completed = record.completed || isCompleted(position, durationMs: next.durationMs)
        next.completed = completed
        next.positionMs = completed && next.durationMs > 0 ? next.durationMs : position
        next.progress = progressOf(positionMs: position, durationMs: next.durationMs, completed: completed)
        next.lastPlayTime = now ?? record.lastPlayTime
        return next
    }

    static func formatClock(_ ms: Int64) -> String {
        let totalSec = max(ms / 1000, 0)
        let hours = totalSec / 3600
        let minutes = (totalSec % 3600) / 60
        let seconds = totalSec % 60
        if hours > 0 {
            return "\(hours):\(pad2(minutes)):\(pad2(seconds))"
        }
        return "\(minutes):\(pad2(seconds))"
    }

    static func progressLabel(_ record: WatchHistoryRecord) -> String {
        if record.completed { return "已看完" }
        return "已播放 \(formatClock(record.positionMs)) / \(formatClock(record.durationMs))"
    }

    static func fromPlayback(
        item: VodItem,
        episode: Episode,
        episodeIndex: Int,
        sourceId: Int,
        sourceName: String,
        positionMs: Int64,
        durationMs: Int64,
        now: Int64
    ) -> WatchHistoryRecord {
        normalize(
            WatchHistoryRecord(
                videoId: item.id,
                vodId: item.vodId,
                episodeId: episode.url,
                title: item.vodName,
                episodeTitle: episode.name,
                episodeIndex: max(episodeIndex, 0),
                cover: item.vodPic,
                sourceId: sourceId,
                sourceName: sourceName,
                positionMs: positionMs,
                durationMs: durationMs,
                lastPlayTime: now
            ),
            now: now
        )
    }

    private static func pad2(_ value: Int64) -> String {
        String(format: "%02d", value)
    }
}

enum WatchHistoryDisplay {
    private static let qualityOnly = try! NSRegularExpression(
        pattern: #"^(?:U?HD|FHD|UHD|4K|8K|720P|1080P|2160P|蓝光|高清|超清|流畅|正片|预告|花絮|全集|完整版)$"#,
        options: [.caseInsensitive]
    )

    static func heading() -> String { "接着看" }

    static func continueAction(clock: String) -> String { "从 \(clock) 继续" }

    static func restartAction() -> String { "从头播放" }

    static func episodeLine(title: String, episodeTitle: String) -> String? {
        let episode = episodeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if episode.isEmpty { return nil }
        if episode.caseInsensitiveCompare(title.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
            return nil
        }
        let range = NSRange(episode.startIndex..<episode.endIndex, in: episode)
        if qualityOnly.firstMatch(in: episode, range: range) != nil {
            return nil
        }
        return episode
    }

    static func showProgressBar(_ durationMs: Int64) -> Bool {
        durationMs > 0
    }
}

struct WatchHistoryPlayback {
    let item: VodItem
    let candidates: [PlaybackCandidate]
    let resumePositionMs: Int64
    let sourceName: String
    let episodeIndex: Int
}

enum WatchHistoryResume {
    static func lookup(store: WatchHistoryStore, item: VodItem) -> WatchHistoryRecord? {
        if let record = store.getByVideoId(item.id) { return record }
        let vodId = item.vodId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vodId.isEmpty else { return nil }
        return store.getAll().first { record in
            record.vodId == vodId && (record.sourceId == 0 || record.sourceId == item.resolvedSourceId)
        }
    }

    static func resumePositionMs(_ record: WatchHistoryRecord) -> Int64 {
        if record.completed { return 0 }
        return WatchHistoryProgress.sanitizePosition(record.positionMs, durationMs: record.durationMs)
    }

    static func playbackRequest(
        detail: DetailResponse,
        sourceIndex: Int,
        episode: Episode,
        resumePositionMs: Int64 = 0
    ) -> WatchHistoryPlayback {
        let source = detail.playSources.indices.contains(sourceIndex) ? detail.playSources[sourceIndex] : nil
        return WatchHistoryPlayback(
            item: detail.vod,
            candidates: VodPlaybackFailover.candidates(
                playSources: detail.playSources,
                selectedIndex: sourceIndex,
                episode: episode,
                fallbackSourceId: detail.vod.resolvedSourceId
            ),
            resumePositionMs: max(resumePositionMs, 0),
            sourceName: source?.name ?? "",
            episodeIndex: episodeIndex(source: source, episode: episode)
        )
    }

    static func playbackRequest(
        detail: DetailResponse,
        record: WatchHistoryRecord,
        restart: Bool = false
    ) -> WatchHistoryPlayback? {
        guard let match = findEpisode(detail: detail, record: record) else { return nil }
        return playbackRequest(
            detail: detail,
            sourceIndex: match.0,
            episode: match.1,
            resumePositionMs: restart ? 0 : resumePositionMs(record)
        )
    }

    static func findEpisode(detail: DetailResponse, record: WatchHistoryRecord) -> (Int, Episode)? {
        let sources = detail.playSources
        guard !sources.isEmpty else { return nil }
        let preferred = sources.firstIndex { source in
            (source.sourceId ?? detail.vod.resolvedSourceId) == record.sourceId
        } ?? 0
        let ordered = [sources[preferred]] + sources.enumerated().compactMap { index, source in
            index == preferred ? nil : source
        }
        for source in ordered {
            guard let episode = matchEpisode(source: source, record: record) else { continue }
            let sourceIndex = sources.firstIndex(where: { $0.key == source.key }) ?? preferred
            return (sourceIndex, episode)
        }
        return nil
    }

    static func episodeIndex(source: PlaySource?, episode: Episode) -> Int {
        guard let source else { return 0 }
        if let index = source.episodes.firstIndex(where: { $0.url == episode.url && $0.name == episode.name }) {
            return index
        }
        if let index = source.episodes.firstIndex(where: { $0.url == episode.url }) {
            return index
        }
        return max(source.episodes.firstIndex(where: { $0.name == episode.name }) ?? 0, 0)
    }

    private static func matchEpisode(source: PlaySource, record: WatchHistoryRecord) -> Episode? {
        if !record.episodeId.isEmpty, let match = source.episodes.first(where: { $0.url == record.episodeId }) {
            return match
        }
        if !record.episodeTitle.isEmpty, let match = source.episodes.first(where: { $0.name == record.episodeTitle }) {
            return match
        }
        if source.episodes.indices.contains(record.episodeIndex) {
            return source.episodes[record.episodeIndex]
        }
        return source.episodes.first
    }
}

protocol WatchHistoryPersistence {
    func load() -> String?
    func save(_ json: String)
}

final class MemoryWatchHistoryPersistence: WatchHistoryPersistence {
    private var json: String?

    func load() -> String? { json }

    func save(_ json: String) {
        self.json = json
    }
}

final class FileWatchHistoryPersistence: WatchHistoryPersistence {
    private let file: URL

    init(file: URL) {
        self.file = file
    }

    func load() -> String? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try? String(contentsOf: file, encoding: .utf8)
    }

    func save(_ json: String) {
        let directory = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tmp = directory.appendingPathComponent(file.lastPathComponent + ".tmp")
        do {
            try json.write(to: tmp, atomically: true, encoding: .utf8)
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            try FileManager.default.moveItem(at: tmp, to: file)
        } catch {
            try? json.write(to: file, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}

final class WatchHistoryStore {
    static let defaultMaxSize = 100

    private let persistence: WatchHistoryPersistence
    private let maxSize: Int
    private let lock = NSLock()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    init(persistence: WatchHistoryPersistence, maxSize: Int = WatchHistoryStore.defaultMaxSize) {
        self.persistence = persistence
        self.maxSize = maxSize
    }

    func save(_ record: WatchHistoryRecord) {
        let normalized = WatchHistoryProgress.normalize(record)
        guard !normalized.videoId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var next = loadUnlocked().filter { $0.videoId != normalized.videoId }
        next.insert(normalized, at: 0)
        persistUnlocked(trim(next))
    }

    func getAll() -> [WatchHistoryRecord] {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    func getByVideoId(_ videoId: String) -> WatchHistoryRecord? {
        let key = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return getAll().first { $0.videoId == key }
    }

    func delete(_ videoId: String) {
        let key = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        persistUnlocked(loadUnlocked().filter { $0.videoId != key })
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        persistUnlocked([])
    }

    private func loadUnlocked() -> [WatchHistoryRecord] {
        let raw = persistence.load()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return [] }
        if let document = try? Self.decoder.decode(WatchHistoryDocument.self, from: data) {
            return trim(document.records.map { WatchHistoryProgress.normalize($0) }.filter { !$0.videoId.isEmpty })
        }
        if let records = try? Self.decoder.decode([WatchHistoryRecord].self, from: data) {
            return trim(records.map { WatchHistoryProgress.normalize($0) }.filter { !$0.videoId.isEmpty })
        }
        return []
    }

    private func persistUnlocked(_ records: [WatchHistoryRecord]) {
        guard let data = try? Self.encoder.encode(WatchHistoryDocument(records: records)),
              let json = String(data: data, encoding: .utf8) else { return }
        persistence.save(json)
    }

    private func trim(_ records: [WatchHistoryRecord]) -> [WatchHistoryRecord] {
        var seen = Set<String>()
        return records
            .sorted { $0.lastPlayTime > $1.lastPlayTime }
            .filter { seen.insert($0.videoId).inserted }
            .prefix(max(maxSize, 1))
            .map { $0 }
    }
}

private struct WatchHistoryDocument: Codable {
    var records: [WatchHistoryRecord] = []
}

final class WatchHistoryRecorder {
    private let store: WatchHistoryStore
    private let intervalMs: Int64
    private var lastVideoId: String?
    private var lastWriteAt: Int64 = Int64.min / 2

    init(store: WatchHistoryStore, intervalMs: Int64 = 8_000) {
        self.store = store
        self.intervalMs = intervalMs
    }

    func save(_ record: WatchHistoryRecord, force: Bool) {
        let normalized = WatchHistoryProgress.normalize(record)
        guard !normalized.videoId.isEmpty else { return }
        let now = normalized.lastPlayTime
        let sameItem = lastVideoId == normalized.videoId
        if !force && sameItem && now - lastWriteAt < intervalMs { return }
        lastVideoId = normalized.videoId
        lastWriteAt = now
        store.save(normalized)
    }
}
