import Foundation

struct PlaybackCandidate: Hashable {
    let sourceId: Int
    let episode: Episode
}

enum VodPlaybackFailover {
    /// Primary line first, then other weighted playable lines for the same episode slot.
    static func candidates(
        playSources: [PlaySource],
        selectedIndex: Int,
        episode: Episode,
        fallbackSourceId: Int,
        maxCandidates: Int = 4
    ) -> [PlaybackCandidate] {
        guard !playSources.isEmpty else {
            return [PlaybackCandidate(sourceId: fallbackSourceId, episode: episode)]
        }
        let selected = playSources[min(max(selectedIndex, 0), playSources.count - 1)]
        let episodeIndex = selected.episodes.firstIndex(where: { $0.url == episode.url && $0.name == episode.name })
            ?? selected.episodes.firstIndex(where: { $0.url == episode.url })
            ?? selected.episodes.firstIndex(where: { $0.name == episode.name })
            ?? 0

        var result: [PlaybackCandidate] = []
        var seen = Set<String>()

        func append(_ source: PlaySource, ep: Episode) {
            let sourceId = source.sourceId ?? fallbackSourceId
            let key = "\(sourceId)|\(ep.url)"
            guard seen.insert(key).inserted else { return }
            result.append(PlaybackCandidate(sourceId: sourceId, episode: ep))
        }

        append(selected, ep: episode)

        let ordered = PlayLineWeighting.sort(playSources)
        for source in ordered {
            if source.key == selected.key { continue }
            guard let ep = episodeMatching(source: source, episodeIndex: episodeIndex, preferredName: episode.name) else {
                continue
            }
            guard PlaybackSupport.isDirectMediaURL(ep.url) else { continue }
            append(source, ep: ep)
            if result.count >= maxCandidates { break }
        }
        return result
    }

    static func nextIndex(after index: Int, count: Int) -> Int? {
        let next = index + 1
        return next < count ? next : nil
    }

    private static func episodeMatching(
        source: PlaySource,
        episodeIndex: Int,
        preferredName: String
    ) -> Episode? {
        if episodeIndex < source.episodes.count {
            let byIndex = source.episodes[episodeIndex]
            if PlaybackSupport.isDirectMediaURL(byIndex.url) {
                return byIndex
            }
        }
        if let byName = source.episodes.first(where: {
            $0.name == preferredName && PlaybackSupport.isDirectMediaURL($0.url)
        }) {
            return byName
        }
        return source.episodes.first(where: { PlaybackSupport.isDirectMediaURL($0.url) })
    }
}

enum VodMediaProbe {
    /// Quick playlist/file check so dead CDNs fail before the 15s AVPlayer start timeout.
    static func isLikelyPlayable(
        url: URL,
        headers: [String: String],
        timeout: TimeInterval = 6
    ) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("bytes=0-2047", forHTTPHeaderField: "Range")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
            let decision = HLSPlaylistProbe.evaluate(
                statusCode: status,
                contentType: contentType,
                body: data,
                pendingAttempt: 0
            )
            switch decision {
            case .playable, .flv, .mpegts:
                return true
            case .retry, .reject:
                return false
            }
        } catch {
            return false
        }
    }
}
