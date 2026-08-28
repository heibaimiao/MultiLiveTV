import Foundation

enum M3UPlaylistParser {
    static let ungrouped = "未分组"

    static func parse(_ text: String) -> [LiveGroup] {
        parseM3U(normalizedLines(text))
    }

    /// M3U 或 TVBox/DIYP 的 `分组,#genre#` + `台名,地址` 文本。
    static func parsePlaylist(_ text: String) -> [LiveGroup] {
        let lines = normalizedLines(text)
        if looksLikeM3U(lines) {
            return parseM3U(lines)
        }
        return parseTxt(lines)
    }

    private static func normalizedLines(_ text: String) -> [String] {
        var normalized = text
        if normalized.hasPrefix("\u{FEFF}") {
            normalized.removeFirst()
        }
        return normalized
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func looksLikeM3U(_ lines: [String]) -> Bool {
        lines.contains { line in
            let upper = line.uppercased()
            return upper.hasPrefix("#EXTM3U") || upper.hasPrefix("#EXTINF:")
        }
    }

    private static func parseM3U(_ lines: [String]) -> [LiveGroup] {

        var groupOrder: [String] = []
        var channelsByGroup: [String: [LiveChannel]] = [:]
        var pending: (name: String, group: String, logo: String?, headers: [String: String])?

        func commit(line: String) {
            guard let pending else { return }
            let parts = LivePlayback.splitKodiLine(line)
            guard let url = playableMediaURL(from: parts.url) else { return }
            var headers = pending.headers
            headers.merge(LivePlayback.headersFromKodiSuffix(parts.suffix)) { _, new in new }
            let stream = LiveStream(url: url, headers: headers)
            let group = pending.group.isEmpty ? ungrouped : pending.group
            if !groupOrder.contains(group) {
                groupOrder.append(group)
            }
            var list = channelsByGroup[group] ?? []
            if let index = list.firstIndex(where: { $0.name == pending.name }) {
                if !list[index].streams.contains(where: { $0.url == url }) {
                    list[index].streams.append(stream)
                }
                if list[index].logo == nil {
                    list[index].logo = pending.logo
                }
            } else {
                list.append(
                    LiveChannel(name: pending.name, group: group, logo: pending.logo, streams: [stream])
                )
            }
            channelsByGroup[group] = list
        }

        for line in lines {
            if line.isEmpty { continue }
            if line.uppercased().hasPrefix("#EXTINF:") {
                let ext = parseExtInf(line)
                pending = (ext.name, ext.group, ext.logo, [:])
                continue
            }
            if line.uppercased().hasPrefix("#EXTVLCOPT:") {
                if var current = pending, let parsed = LivePlayback.headerFromEXTVLCOPT(line) {
                    current.headers[parsed.name] = parsed.value
                    pending = current
                }
                continue
            }
            if line.hasPrefix("#") { continue }
            if pending != nil {
                commit(line: line)
                pending = nil
            }
        }

        return groupOrder.map { LiveGroup(name: $0, channels: channelsByGroup[$0] ?? []) }
    }

    private static func parseTxt(_ lines: [String]) -> [LiveGroup] {
        var groupOrder: [String] = []
        var channelsByGroup: [String: [LiveChannel]] = [:]
        var currentGroup = ungrouped

        for line in expandedTxtLines(lines) {
            if line.isEmpty { continue }
            if let genre = txtGenreName(line) {
                currentGroup = genre.isEmpty ? ungrouped : genre
                continue
            }
            guard let comma = line.firstIndex(of: ",") else { continue }
            let name = String(line[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            for raw in txtURLs(from: rest) {
                let parts = LivePlayback.splitKodiLine(raw)
                guard let url = playableMediaURL(from: parts.url) else { continue }
                appendStream(
                    LiveStream(url: url, headers: LivePlayback.headersFromKodiSuffix(parts.suffix)),
                    name: name,
                    group: currentGroup,
                    logo: nil,
                    groupOrder: &groupOrder,
                    channelsByGroup: &channelsByGroup
                )
            }
        }

        return groupOrder.map { LiveGroup(name: $0, channels: channelsByGroup[$0] ?? []) }
    }

    /// 源列表常把 `,江苏卫视,url` 或 `url1频道名,url2` 粘在一行。
    static func expandedTxtLines(_ lines: [String]) -> [String] {
        var expanded: [String] = []
        for line in lines {
            var current = line
            while current.hasPrefix(",") {
                current = String(current.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            expanded.append(contentsOf: splitGluedChannelLines(current))
        }
        return expanded
    }

    static func splitGluedChannelLines(_ line: String) -> [String] {
        let pattern = #"([A-Za-z0-9./?=&%~_+-])(\p{Han}+,https?://)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [line]
        }
        let range = NSRange(line.startIndex..., in: line)
        let split = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "$1\n$2")
        return split
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func txtGenreName(_ line: String) -> String? {
        let marker = "#genre#"
        guard let range = line.range(of: marker, options: .caseInsensitive) else { return nil }
        let before = line[..<range.lowerBound]
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
        return before
    }

    private static func txtURLs(from rest: String) -> [String] {
        var pieces: [String] = []
        for chunk in rest.split(separator: "#", omittingEmptySubsequences: true) {
            let trimmed = String(chunk).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains(",") {
                for part in trimmed.split(separator: ",", omittingEmptySubsequences: true) {
                    let url = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
                    if url.contains("://") {
                        pieces.append(url)
                    }
                }
            } else if trimmed.contains("://") {
                pieces.append(trimmed)
            }
        }
        return pieces
    }

    private static func appendStream(
        _ stream: LiveStream,
        name: String,
        group: String,
        logo: String?,
        groupOrder: inout [String],
        channelsByGroup: inout [String: [LiveChannel]]
    ) {
        if !groupOrder.contains(group) {
            groupOrder.append(group)
        }
        var list = channelsByGroup[group] ?? []
        if let index = list.firstIndex(where: { $0.name == name }) {
            if !list[index].streams.contains(where: { $0.url == stream.url }) {
                list[index].streams.append(stream)
            }
            if list[index].logo == nil {
                list[index].logo = logo
            }
        } else {
            list.append(LiveChannel(name: name, group: group, logo: logo, streams: [stream]))
        }
        channelsByGroup[group] = list
    }

    static func merge(_ playlists: [[LiveGroup]]) -> [LiveGroup] {
        var groupOrder: [String] = []
        var channelsByGroup: [String: [LiveChannel]] = [:]

        for playlist in playlists {
            for group in playlist {
                if !groupOrder.contains(group.name) {
                    groupOrder.append(group.name)
                }
                var list = channelsByGroup[group.name] ?? []
                for channel in group.channels {
                    if let index = list.firstIndex(where: { $0.name == channel.name }) {
                        for stream in channel.streams where !list[index].streams.contains(where: { $0.url == stream.url }) {
                            list[index].streams.append(stream)
                        }
                        if list[index].logo == nil {
                            list[index].logo = channel.logo
                        }
                    } else {
                        list.append(channel)
                    }
                }
                channelsByGroup[group.name] = list
            }
        }

        return groupOrder.map { LiveGroup(name: $0, channels: channelsByGroup[$0] ?? []) }
    }

    static func mediaURL(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPipe: String
        if let pipe = trimmed.firstIndex(of: "|") {
            withoutPipe = String(trimmed[..<pipe]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            withoutPipe = trimmed
        }
        return LivePlayback.stripSourceTag(withoutPipe)
    }

    /// 仅保留 HTTP/HTTPS。裸 rtp/rtmp/udp 无法播放；HTTP-UDPXY 由 VLC 承接。
    static func playableMediaURL(from line: String) -> String? {
        let url = mediaURL(from: line)
        guard RemoteMediaURL.parse(url) != nil else { return nil }
        return url
    }

    private static func parseExtInf(_ line: String) -> (name: String, group: String, logo: String?) {
        let rest = String(line.dropFirst("#EXTINF:".count))
        guard let comma = rest.lastIndex(of: ",") else {
            return (name: rest, group: ungrouped, logo: nil)
        }
        let meta = String(rest[..<comma])
        let name = String(rest[rest.index(after: comma)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let group = attribute(meta, key: "group-title") ?? ungrouped
        let logo = attribute(meta, key: "tvg-logo")
        return (name: name.isEmpty ? rest : name, group: group, logo: logo)
    }

    private static func attribute(_ text: String, key: String) -> String? {
        guard let start = text.range(of: "\(key)=", options: .caseInsensitive) else { return nil }
        var rest = text[start.upperBound...].trimmingCharacters(in: .whitespaces)
        guard let first = rest.first else { return nil }
        if first == "\"" || first == "'" {
            rest.removeFirst()
            guard let end = rest.firstIndex(of: first) else { return nil }
            let value = String(rest[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        let value = rest.prefix(while: { !$0.isWhitespace })
        let trimmed = String(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum LivePlayback {
    /// 去掉 TVBox/DIYP 常见的 `$源名` 尾巴；查询参数里的 `$` 原样保留。
    static func stripSourceTag(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dollar = trimmed.firstIndex(of: "$") else { return trimmed }
        let suffix = String(trimmed[trimmed.index(after: dollar)...])
        if suffix.contains("=") || suffix.contains("&") || suffix.contains("/") || suffix.contains("://") {
            return trimmed
        }
        return String(trimmed[..<dollar])
    }

    /// UDPXY 的 `/udp/` `/rtp/` 是无限 MPEG-TS，不能走 HLS URLSession 探测。
    static func prefersVLC(for url: String) -> Bool {
        let lower = stripSourceTag(url).lowercased()
        return lower.contains("/udp/") || lower.contains("/rtp/")
    }

    /// AVPlayer 解不了 MPEG-2 电信源、HTTP 602 分片时，同一地址再交给 VLC。
    static func shouldRetryWithVLC(alreadyUsedVLC: Bool, vlcAvailable: Bool) -> Bool {
        vlcAvailable && !alreadyUsedVLC
    }

    enum Renderer: Equatable {
        case avPlayer
        case vlc
    }

    /// AVPlayer 无法忽略过期证书；探测阶段放宽 TLS 后的 HLS 必须走 VLC。
    static func renderer(decision: HLSPlaylistProbe.Decision, relaxedTLS: Bool) -> Renderer? {
        switch decision {
        case .playable:
            return relaxedTLS ? .vlc : .avPlayer
        case .flv, .mpegts:
            return .vlc
        case .retry, .reject:
            return nil
        }
    }

    static func nextURLIndex(after current: Int, count: Int) -> Int? {
        let next = current + 1
        return next < count ? next : nil
    }

    static func cycleURLIndex(after current: Int, count: Int) -> Int? {
        guard count > 1 else { return nil }
        return (current + 1) % count
    }

    static func shouldApplyFailure(eventGeneration: Int, currentGeneration: Int) -> Bool {
        eventGeneration == currentGeneration
    }

    static func splitKodiLine(_ line: String) -> (url: String, suffix: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pipe = trimmed.firstIndex(of: "|") else { return (trimmed, "") }
        let url = String(trimmed[..<pipe]).trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(trimmed[trimmed.index(after: pipe)...])
        return (url, suffix)
    }

    static func headersFromKodiSuffix(_ suffix: String) -> [String: String] {
        var headers: [String: String] = [:]
        guard !suffix.isEmpty else { return headers }
        for pair in suffix.split(separator: "&") {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let rawKey = String(pair[..<eq])
            let rawValue = String(pair[pair.index(after: eq)...])
            guard let name = canonicalHeaderName(rawKey) else { continue }
            headers[name] = rawValue.removingPercentEncoding ?? rawValue
        }
        return headers
    }

    static func headerFromEXTVLCOPT(_ line: String) -> (name: String, value: String)? {
        let prefix = "#EXTVLCOPT:"
        guard line.uppercased().hasPrefix(prefix) else { return nil }
        let rest = String(line.dropFirst(prefix.count))
        guard let eq = rest.firstIndex(of: "=") else { return nil }
        let rawKey = String(rest[..<eq])
        let rawValue = String(rest[rest.index(after: eq)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name = canonicalHeaderName(rawKey), !rawValue.isEmpty else { return nil }
        return (name, rawValue.removingPercentEncoding ?? rawValue)
    }

    static func canonicalHeaderName(_ key: String) -> String? {
        switch key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "user-agent", "http-user-agent": return "User-Agent"
        case "referer", "referrer", "http-referer", "http-referrer": return "Referer"
        case "origin", "http-origin": return "Origin"
        case "cookie", "http-cookie": return "Cookie"
        default: return nil
        }
    }

    static func cookieHeader(from response: URLResponse, storage: HTTPCookieStorage? = nil) -> String? {
        guard let url = response.url else { return nil }
        var byName: [String: String] = [:]
        if let http = response as? HTTPURLResponse {
            var fields: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String {
                    fields[key] = value
                }
            }
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
                byName[cookie.name] = cookie.value
            }
        }
        if let storage, let cookies = storage.cookies(for: url) {
            for cookie in cookies {
                byName[cookie.name] = cookie.value
            }
        }
        guard !byName.isEmpty else { return nil }
        return byName.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
    }

    static func playerHeaders(kodi: [String: String], cookieHeader: String?) -> [String: String] {
        var headers = kodi
        if let cookieHeader, !cookieHeader.isEmpty {
            if let existing = headers["Cookie"], !existing.isEmpty {
                headers["Cookie"] = existing + "; " + cookieHeader
            } else {
                headers["Cookie"] = cookieHeader
            }
        }
        return headers
    }

    static func vlcHTTPOptions(headers: [String: String]) -> [String] {
        var options: [String] = []
        let mapping = [
            ("User-Agent", "http-user-agent"),
            ("Referer", "http-referrer"),
            ("Cookie", "http-cookie"),
        ]
        for (header, option) in mapping {
            if let value = headers[header], !value.isEmpty {
                options.append(":\(option)=\(value)")
            }
        }
        options.append(":http-tls-verify=0")
        options.append(":tls-verify=0")
        return options
    }

    static func warmedCookieHeader(for url: URL, session: URLSession? = nil) async -> String? {
        let ownedSession: URLSession
        if let session {
            ownedSession = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = NetworkConfig.requestTimeout
            config.httpAdditionalHeaders = ["User-Agent": NetworkConfig.userAgent]
            ownedSession = URLSession(configuration: config)
        }
        defer {
            if session == nil {
                ownedSession.finishTasksAndInvalidate()
            }
        }
        guard let (_, response) = try? await ownedSession.data(from: url) else { return nil }
        return cookieHeader(from: response, storage: ownedSession.configuration.httpCookieStorage)
    }
}

enum LiveHTTP {
    static func isSuccess(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }
}
