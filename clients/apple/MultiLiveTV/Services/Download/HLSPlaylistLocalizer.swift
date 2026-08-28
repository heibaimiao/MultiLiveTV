import Foundation

enum HLSPlaylistLocalizer {
    struct Download: Equatable {
        let remote: URL
        let localName: String
    }

    struct Plan: Equatable {
        let playlist: String
        let downloads: [Download]
    }

    static func isMasterPlaylist(_ text: String) -> Bool {
        text.contains("#EXT-X-STREAM-INF")
    }

    static func pickVariantURL(playlist: String, base: URL, maxBandwidth: Int) -> URL? {
        let lines = playlist.components(separatedBy: .newlines)
        var candidates: [(bandwidth: Int, url: String)] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                let bandwidth = parseAttribute(line, name: "BANDWIDTH").flatMap(Int.init) ?? 0
                index += 1
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    if next.isEmpty || next.hasPrefix("#") {
                        index += 1
                        continue
                    }
                    candidates.append((bandwidth, next))
                    break
                }
            }
            index += 1
        }

        let underCap = candidates.filter { $0.bandwidth <= maxBandwidth }
        let chosen = (underCap.max { $0.bandwidth < $1.bandwidth })
            ?? candidates.min { $0.bandwidth < $1.bandwidth }
        return chosen.flatMap { resolve($0.url, relativeTo: base) }
    }

    static func plan(mediaPlaylist: String, base: URL) -> Plan {
        var downloads: [Download] = []
        var output: [String] = []
        var segmentIndex = 0
        var keyIndex = 0
        var mapIndex = 0

        for raw in mediaPlaylist.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#EXT-X-KEY") {
                output.append(rewriteTaggedURI(trimmed, attribute: "URI", downloads: &downloads, base: base, localName: "key_\(keyIndex).key"))
                keyIndex += 1
            } else if trimmed.hasPrefix("#EXT-X-MAP") {
                output.append(rewriteTaggedURI(trimmed, attribute: "URI", downloads: &downloads, base: base, localName: "map_\(mapIndex).mp4"))
                mapIndex += 1
            } else if trimmed.hasPrefix("#") || trimmed.isEmpty {
                output.append(raw)
            } else {
                guard let remote = resolve(trimmed, relativeTo: base) else {
                    output.append(raw)
                    continue
                }
                let ext = remote.pathExtension.isEmpty ? "ts" : remote.pathExtension
                let localName = String(format: "seg_%04d.%@", segmentIndex, ext)
                downloads.append(Download(remote: remote, localName: localName))
                output.append(localName)
                segmentIndex += 1
            }
        }

        return Plan(playlist: output.joined(separator: "\n"), downloads: downloads)
    }

    static func resolve(_ reference: String, relativeTo base: URL) -> URL? {
        if let absolute = URL(string: reference), absolute.scheme != nil {
            return absolute
        }
        return URL(string: reference, relativeTo: base)?.absoluteURL
    }

    private static func rewriteTaggedURI(
        _ line: String,
        attribute: String,
        downloads: inout [Download],
        base: URL,
        localName: String
    ) -> String {
        guard let uri = parseQuotedAttribute(line, name: attribute),
              let remote = resolve(uri, relativeTo: base) else {
            return line
        }
        downloads.append(Download(remote: remote, localName: localName))
        return replaceQuotedAttribute(line, name: attribute, value: localName)
    }

    private static func parseAttribute(_ line: String, name: String) -> String? {
        if let quoted = parseQuotedAttribute(line, name: name) {
            return quoted
        }
        let pattern = "\(name)="
        guard let range = line.range(of: pattern) else { return nil }
        let rest = line[range.upperBound...]
        let end = rest.firstIndex(where: { $0 == "," || $0 == " " }) ?? rest.endIndex
        return String(rest[..<end])
    }

    private static func parseQuotedAttribute(_ line: String, name: String) -> String? {
        let pattern = "\(name)=\""
        guard let start = line.range(of: pattern) else { return nil }
        let rest = line[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    private static func replaceQuotedAttribute(_ line: String, name: String, value: String) -> String {
        let pattern = "\(name)=\""
        guard let start = line.range(of: pattern) else { return line }
        let rest = line[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return line }
        let prefix = line[..<start.upperBound]
        let suffix = line[end...]
        return "\(prefix)\(value)\(suffix)"
    }
}
