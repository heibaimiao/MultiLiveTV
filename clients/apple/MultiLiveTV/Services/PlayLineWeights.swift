import Foundation

struct PlayLineWeights: Codable {
    let version: Int
    let defaultWeight: Int
    let byPlayFrom: [String: Int]
    let byProviderId: [String: Int]
    let bySourceId: [String: Int]?

    static let bundled: PlayLineWeights = {
        if let url = Bundle.main.url(forResource: "play-line-weights", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let table = try? JSONDecoder().decode(PlayLineWeights.self, from: data) {
            return table
        }
        return PlayLineWeights(
            version: 2,
            defaultWeight: 100,
            byPlayFrom: [
                "qq": 2000,
                "腾讯": 2000,
                "腾讯视频": 2000,
                "qiyi": 1990,
                "爱奇艺": 1990,
                "youku": 1980,
                "优酷": 1980,
                "mgtv": 1970,
                "芒果": 1970,
                "芒果TV": 1970,
                "huo": 1900,
                "lv2": 1890,
                "rrys": 1880,
                "bytedance": 1870,
                "dong": 1860,
                "cloudflare": 1850,
                "cloudflare-4k": 1840,
                "hnm3u8": 920,
            ],
            byProviderId: [
                "official-qq": 2000,
                "official-qiyi": 1990,
                "official-youku": 1980,
                "official-mgtv": 1970,
                "official-v": 1900,
                "bytevod-lv2": 1890,
                "official-r": 1880,
                "bytedance": 1870,
                "dong": 1860,
                "bytevod-cloudflare": 1850,
                "bytevod-cloudflare-4k": 1840,
                "official-hot-playback": 1830,
            ],
            bySourceId: [:]
        )
    }()

    func weight(playFrom: String?, providerId: String?, sourceId: Int? = nil) -> Int {
        if let providerId, let value = byProviderId[providerId] {
            return value
        }
        if let playFrom, let value = byPlayFrom[playFrom] {
            return value
        }
        if let sourceId, sourceId != 0,
           let value = bySourceId?[String(sourceId)] {
            return value
        }
        return defaultWeight
    }
}

enum PlayLineWeighting {
    static var table: PlayLineWeights = .bundled
    /// When false, ticket/official lines are skipped for default selection.
    /// Apple clients currently show official lines only, so keep enabled.
    static var ticketEnabled: Bool = true
    static var healthStore: SourceHealthStore = .shared
    /// Optional play_priority lookup from Source registry (numericId → priority).
    static var playPriorityBySourceId: [Int: Int] = [:]

    static func weight(playFrom: String?, providerId: String? = nil, sourceId: Int? = nil) -> Int {
        table.weight(playFrom: playFrom, providerId: providerId, sourceId: sourceId)
    }

    static func sourceWeight(_ sourceId: Int) -> Int {
        if let playPriority = playPriorityBySourceId[sourceId] {
            return playPriority
        }
        return weight(playFrom: nil, providerId: nil, sourceId: sourceId)
    }

    static func metadataWeight(_ sourceId: Int, store: SourceStore? = nil) -> Int {
        if let store {
            return store.metadataPriority(for: sourceId)
        }
        return sourceWeight(sourceId)
    }

    static func effectivePlayScore(
        playFrom: String?,
        providerId: String?,
        sourceId: Int?,
        baseWeight: Int = 0
    ) -> Int {
        let tableW: Int
        if let providerId, let value = table.byProviderId[providerId] {
            tableW = value
        } else if let playFrom, let value = table.byPlayFrom[playFrom] {
            tableW = value
        } else if let sourceId, sourceId != 0 {
            tableW = playPriorityBySourceId[sourceId]
                ?? table.bySourceId?[String(sourceId)]
                ?? table.defaultWeight
        } else {
            tableW = table.defaultWeight
        }
        let resolved = baseWeight > 0 ? baseWeight : tableW
        let health = sourceId.map { healthStore.healthScore(for: $0) } ?? 0
        return resolved + health
    }

    /// Detail UI: keep every line, sorted by effective play weight (official platforms rank first).
    static func forDetailDisplay(_ sources: [PlaySource]) -> [PlaySource] {
        sort(sources.map { annotate($0) })
    }

    static func annotate(_ source: PlaySource, rawPlayFrom: String? = nil) -> PlaySource {
        let playFrom = (rawPlayFrom ?? source.playFrom ?? source.key)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedWeight = effectivePlayScore(
            playFrom: playFrom,
            providerId: source.providerId,
            sourceId: source.sourceId,
            baseWeight: source.weight
        )
        return PlaySource(
            name: source.name,
            key: source.key,
            episodes: source.episodes,
            sourceId: source.sourceId,
            weight: resolvedWeight,
            mode: source.mode.isEmpty ? "direct" : source.mode,
            playFrom: playFrom,
            providerId: source.providerId,
            ticket: source.ticket,
            requiresAuth: source.requiresAuth
        )
    }

    static func sort(_ sources: [PlaySource]) -> [PlaySource] {
        sources.sorted { lhs, rhs in
            if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
            let ls = playabilityScore(lhs)
            let rs = playabilityScore(rhs)
            if ls != rs { return ls > rs }
            return lhs.episodes.count > rhs.episodes.count
        }
    }

    static func preferredIndex(in sources: [PlaySource], episodeIndex: Int = 0) -> Int {
        preferredPlayableIndex(in: sources, episodeIndex: episodeIndex, ticketEnabled: ticketEnabled)
    }

    static func preferredPlayableIndex(
        in sources: [PlaySource],
        episodeIndex: Int = 0,
        ticketEnabled: Bool
    ) -> Int {
        guard !sources.isEmpty else { return 0 }
        let sorted = sort(sources)
        for candidate in sorted {
            guard episodePlayable(candidate, episodeIndex: episodeIndex, ticketEnabled: ticketEnabled) else {
                continue
            }
            if let index = sources.firstIndex(where: { $0.key == candidate.key }) {
                return index
            }
        }
        return 0
    }

    static func nextPlayableIndexes(
        in sources: [PlaySource],
        fromIndex: Int,
        episodeIndex: Int = 0,
        ticketEnabled: Bool,
        maxTries: Int = 3
    ) -> [Int] {
        let ordered = sort(sources)
        var result: [Int] = []
        var seenCurrent = false
        for candidate in ordered {
            guard let index = sources.firstIndex(where: { $0.key == candidate.key }) else { continue }
            if !seenCurrent {
                if index == fromIndex { seenCurrent = true }
                continue
            }
            guard episodePlayable(candidate, episodeIndex: episodeIndex, ticketEnabled: ticketEnabled) else {
                continue
            }
            result.append(index)
            if result.count >= maxTries - 1 { break }
        }
        return result
    }

    private static func episodePlayable(
        _ source: PlaySource,
        episodeIndex: Int,
        ticketEnabled: Bool
    ) -> Bool {
        let ep = episodeIndex < source.episodes.count
            ? source.episodes[episodeIndex]
            : source.episodes.first
        let url = (ep?.url ?? source.ticket ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return false }
        if source.mode == "ticket" { return ticketEnabled }
        // Prefer lines AVPlayer can open directly; skip share/jiexi/html pages.
        return PlaybackSupport.isDirectMediaURL(url)
    }

    private static func playabilityScore(_ source: PlaySource) -> Int {
        source.episodes.filter { PlaybackSupport.isDirectMediaURL($0.url) }.count
    }
}
