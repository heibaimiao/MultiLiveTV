import Foundation

enum PlayParser {
    private static let playSourceNames: [String: String] = [
        "wjm3u8": "无尽", "snm3u8": "索尼", "ikm3u8": "爱酷", "ffm3u8": "非凡",
        "feifan": "非凡", "gsm3u8": "光速", "gsyun": "光速", "mtm3u8": "茅台",
        "mtyun": "茅台", "mym3u8": "猫眼", "hym3u8": "虎牙直链", "hyyun": "虎牙云",
        "modum3u8": "魔都", "liangzi": "量子", "jsyun": "极速", "subyun": "速播",
        "lzm3u8": "量子", "jpm3u8": "极品", "jsm3u8": "极速", "subm3u8": "速播",
        "bfzym3u8": "暴风", "hnm3u8": "红牛", "hnyun": "红牛", "bjm3u8": "八戒",
        "wolong": "卧龙", "maotai": "茅台", "maoyan": "猫眼", "kcm3u8": "快车",
        "xlm3u8": "新浪", "dbm3u8": "豆瓣", "hkm3u8": "华为", "yym3u8": "丫丫",
        "ckm3u8": "CK", "dym3u8": "电影", "ukm3u8": "UK", "lsm3u8": "乐视",
        "qhm3u8": "奇虎", "ysm3u8": "影视", "huyam3u8": "虎牙", "tpm3u8": "淘片",
        "tkm3u8": "天空", "1080zyk": "1080看", "zuidam3u8": "最大", "kuaikan": "快看",
    ]

    private static let playSourcePrefixNames: [String: String] = [
        "wj": "无尽", "sn": "索尼", "ik": "爱酷", "lz": "量子", "ff": "非凡",
        "gs": "光速", "mt": "茅台", "my": "猫眼", "hy": "虎牙", "modu": "魔都",
        "jp": "极品", "js": "极速", "sub": "速播", "bfzy": "暴风", "hn": "红牛",
        "bj": "八戒", "kc": "快车", "xl": "新浪", "db": "豆瓣", "hk": "华为",
        "yy": "丫丫", "ck": "CK", "dy": "电影", "uk": "UK", "ls": "乐视",
        "qh": "奇虎", "ys": "影视", "tp": "淘片", "tk": "天空", "wolong": "卧龙",
        "feifan": "非凡", "maotai": "茅台", "maoyan": "猫眼", "gsyun": "光速",
        "mtyun": "茅台", "hyyun": "虎牙云", "liangzi": "量子", "jsyun": "极速", "subyun": "速播",
    ]

    private static let m3u8Pattern = try! NSRegularExpression(
        pattern: #"https?://[^\s"'<>]+\.m3u8[^\s"'<>]*"#,
        options: .caseInsensitive
    )

    private static let iframePlayerPattern = try! NSRegularExpression(
        pattern: #"src="([^"]*playm3u8\.php\?url=[^"]+)""#,
        options: .caseInsensitive
    )

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = NetworkConfig.requestTimeout
        config.timeoutIntervalForResource = NetworkConfig.requestTimeout
        return URLSession(configuration: config)
    }()

    static func parsePlayURL(vodPlayFrom: String, vodPlayURL: String) -> [PlaySource] {
        guard !vodPlayFrom.isEmpty, !vodPlayURL.isEmpty else { return [] }

        let fromList = splitPlayFrom(vodPlayFrom)
        let urlList: [String]
        if vodPlayURL.contains("$$$") {
            urlList = vodPlayURL.components(separatedBy: "$$$")
        } else {
            urlList = [vodPlayURL]
        }

        var sources: [PlaySource] = []
        for (index, name) in fromList.enumerated() {
            let rawEpisodes: String
            if index < urlList.count {
                rawEpisodes = urlList[index]
            } else if let first = urlList.first {
                rawEpisodes = first
            } else {
                rawEpisodes = ""
            }

            var episodes: [Episode] = []
            for item in rawEpisodes.split(separator: "#", omittingEmptySubsequences: false) {
                let segment = String(item)
                if segment.isEmpty { continue }
                if let dollarIndex = segment.firstIndex(of: "$") {
                    var epName = String(segment[..<dollarIndex])
                    if epName.isEmpty { epName = "播放" }
                    let url = String(segment[segment.index(after: dollarIndex)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !url.isEmpty else { continue }
                    episodes.append(Episode(name: epName, url: url))
                } else {
                    episodes.append(Episode(name: "第\(segment)", url: segment))
                }
            }

            var key = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty { key = "line-\(index + 1)" }
            sources.append(PlayLineWeighting.annotate(PlaySource(
                name: formatPlaySourceName(raw: name, index: index),
                key: key,
                episodes: episodes,
                sourceId: nil,
                playFrom: key
            ), rawPlayFrom: key))
        }
        return sources
    }

    struct VodWithSource {
        let source: Source
        let vod: VodItemRaw
    }

    static func mergePlaySources(from entries: [VodWithSource]) -> [PlaySource] {
        struct RankedPlaySource {
            let playSource: PlaySource
            let vodTime: Int
        }

        var merged: [String: RankedPlaySource] = [:]
        for entry in entries {
            let parsed = parsePlayURL(vodPlayFrom: entry.vod.vodPlayFrom, vodPlayURL: entry.vod.vodPlayURL)
            for line in parsed {
                let playFrom = line.playFrom ?? line.key
                let mergeKey = "\(entry.source.id):\(line.name)"
                let name = displayPlaySourceName(sourceName: entry.source.name, lineName: line.name)
                let ranked = RankedPlaySource(
                    playSource: PlayLineWeighting.annotate(PlaySource(
                        name: name,
                        key: mergeKey,
                        episodes: line.episodes,
                        sourceId: entry.source.id,
                        playFrom: playFrom
                    ), rawPlayFrom: playFrom),
                    vodTime: entry.vod.vodTime
                )
                if let existing = merged[mergeKey], !shouldReplace(existing: existing.playSource, with: ranked.playSource) {
                    continue
                }
                merged[mergeKey] = ranked
            }
        }

        return PlayLineWeighting.sort(merged.values.map(\.playSource))
    }

    static func displayPlaySourceName(sourceName: String, lineName: String) -> String {
        let source = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = lineName.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty { return line }
        if line.isEmpty || source == line { return source }
        if line.hasPrefix(source) { return line }
        return "\(source) · \(line)"
    }

    private static func shouldReplace(existing: PlaySource, with incoming: PlaySource) -> Bool {
        let incomingScore = playabilityScore(incoming)
        let existingScore = playabilityScore(existing)
        if incomingScore != existingScore { return incomingScore > existingScore }
        return incoming.episodes.count > existing.episodes.count
    }

    private static func playabilityScore(_ source: PlaySource) -> Int {
        let directCount = source.episodes.filter { PlaybackSupport.isDirectMediaURL($0.url) }.count
        return directCount
    }

    static func parsePlayAddress(source: Source, playURL: String) async -> ParseResponse {
        let trimmed = playURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParseResponse(url: playURL, parsed: false)
        }

        if isDirectMediaURL(trimmed) {
            return ParseResponse(url: trimmed, parsed: true)
        }

        if let resolved = await resolveFromOriginalPlayPage(trimmed) {
            return ParseResponse(url: resolved, parsed: true)
        }

        guard let jxURL = source.jxUrl, !jxURL.isEmpty else {
            return ParseResponse(url: trimmed, parsed: false)
        }

        guard let encoded = queryEscape(trimmed),
              let url = URL(string: jxURL + encoded) else {
            return ParseResponse(url: trimmed, parsed: false)
        }

        if let resolved = await resolveFromJXEndpoint(url, originalURL: trimmed) {
            return ParseResponse(url: resolved, parsed: true)
        }

        return ParseResponse(url: trimmed, parsed: false)
    }

    private static func resolveFromJXEndpoint(_ url: URL, originalURL: String) async -> String? {
        guard let (data, contentType) = try? await fetch(url) else { return nil }

        if contentType.contains("application/json"),
           let resolved = parseJSONPlaybackURL(data),
           PlaybackSupport.isDirectMediaURL(resolved) {
            return resolved
        }

        let text = normalizeResponseText(data)
        if text.hasPrefix("http"),
           let direct = sanitizePlaybackURL(text.components(separatedBy: .whitespaces).first),
           PlaybackSupport.isDirectMediaURL(direct) {
            return direct
        }

        if let m3u8 = firstM3U8(in: text), PlaybackSupport.isDirectMediaURL(m3u8) {
            return m3u8
        }

        if let iframePath = firstIframePlayerPath(in: text) {
            let playerURL = absoluteJXURL(iframePath, relativeTo: url)
            if let playerURL,
               let (playerData, playerType) = try? await fetch(playerURL) {
                if playerType.contains("application/json"),
                   let resolved = parseJSONPlaybackURL(playerData),
                   PlaybackSupport.isDirectMediaURL(resolved) {
                    return resolved
                }
                let playerText = normalizeResponseText(playerData)
                if let m3u8 = firstM3U8(in: playerText), PlaybackSupport.isDirectMediaURL(m3u8) {
                    return m3u8
                }
                if playerText.hasPrefix("http"),
                   let direct = sanitizePlaybackURL(playerText.components(separatedBy: .whitespaces).first),
                   PlaybackSupport.isDirectMediaURL(direct) {
                    return direct
                }
            }
        }

        return PlaybackSupport.isDirectMediaURL(originalURL) ? originalURL : nil
    }

    static func extractDirectMediaURL(from text: String) -> String? {
        firstM3U8(in: text)
    }

    private static func resolveFromOriginalPlayPage(_ playURL: String) async -> String? {
        guard let url = URL(string: playURL) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(NetworkConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=0-16383", forHTTPHeaderField: "Range")
        if let host = url.host {
            request.setValue("\(url.scheme ?? "https")://\(host)/", forHTTPHeaderField: "Referer")
        }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return nil
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("application/json"),
           let resolved = parseJSONPlaybackURL(data),
           PlaybackSupport.isDirectMediaURL(resolved) {
            return resolved
        }
        let text = normalizeResponseText(data)
        if let m3u8 = extractDirectMediaURL(from: text), PlaybackSupport.isDirectMediaURL(m3u8) {
            return m3u8
        }
        return nil
    }

    private static func fetch(_ url: URL) async throws -> (Data, String) {
        var request = URLRequest(url: url)
        request.setValue(NetworkConfig.userAgent, forHTTPHeaderField: "User-Agent")
        if let host = url.host {
            request.setValue("\(url.scheme ?? "https")://\(host)/", forHTTPHeaderField: "Referer")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return (data, http.value(forHTTPHeaderField: "Content-Type") ?? "")
    }

    private static func parseJSONPlaybackURL(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let urlString = json as? String {
            return sanitizePlaybackURL(urlString)
        }
        if let dict = json as? [String: Any] {
            if let urlString = dict["url"] as? String {
                return sanitizePlaybackURL(urlString)
            }
            if let dataDict = dict["data"] as? [String: Any],
               let urlString = dataDict["url"] as? String {
                return sanitizePlaybackURL(urlString)
            }
        }
        return nil
    }

    private static func normalizeResponseText(_ data: Data) -> String {
        var text = String(data: data, encoding: .utf8) ?? ""
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstM3U8(in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = m3u8Pattern.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return sanitizePlaybackURL(String(text[swiftRange]))
    }

    private static func firstIframePlayerPath(in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = iframePlayerPattern.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[swiftRange]).replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func absoluteJXURL(_ path: String, relativeTo base: URL) -> URL? {
        if path.hasPrefix("http") {
            return URL(string: path)
        }
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.query = nil
        components.path = ""
        let origin = components.string ?? base.absoluteString
        let prefix = origin.hasSuffix("/") ? String(origin.dropLast()) : origin
        return URL(string: prefix + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private static func isDirectMediaURL(_ url: String) -> Bool {
        PlaybackSupport.isDirectMediaURL(url)
    }

    private static func sanitizePlaybackURL(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("\u{FEFF}") {
            value.removeFirst()
        }
        guard value.hasPrefix("http") else { return nil }
        return value
    }

    private static func queryEscape(_ string: String) -> String? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    private static func splitPlayFrom(_ vodPlayFrom: String) -> [String] {
        if vodPlayFrom.isEmpty { return [] }
        if vodPlayFrom.contains("$$$") {
            return vodPlayFrom.components(separatedBy: "$$$").filter { !$0.isEmpty }
        }
        if vodPlayFrom.contains(",") {
            return vodPlayFrom.components(separatedBy: ",").filter { !$0.isEmpty }
        }
        return [vodPlayFrom]
    }

    private static func formatPlaySourceName(raw: String, index: Int) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.isEmpty { return "线路\(index + 1)" }
        if let name = playSourceNames[key] { return name }
        var prefix = key
        if prefix.hasSuffix("m3u8") { prefix = String(prefix.dropLast(4)) }
        if prefix.hasSuffix("yun") { prefix = String(prefix.dropLast(3)) }
        if let name = playSourcePrefixNames[prefix] { return name }
        if raw.range(of: #"^线路\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "线路\(index + 1)"
    }
}
