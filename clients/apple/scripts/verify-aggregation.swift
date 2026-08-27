#!/usr/bin/env swift
import Foundation

// 本地验证：sources 加载 + 跨源搜索合并（不依赖 Go API / Xcode 模拟器）

struct Source: Decodable {
    let id: Int
    let name: String
    let url: String
    let flag: Int
    let vipOnly: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, url, flag
        case vipOnly = "vip_only"
    }
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let scriptDir = scriptURL.deletingLastPathComponent()
let sourcesURL = scriptDir
    .deletingLastPathComponent()
    .appendingPathComponent("MultiLiveTV/Resources/sources.json")

guard FileManager.default.fileExists(atPath: sourcesURL.path) else {
    fputs("missing sources.json\n", stderr)
    exit(1)
}

let sources = try JSONDecoder().decode([Source].self, from: Data(contentsOf: sourcesURL))
let enabled = sources.filter { $0.flag == 0 && ($0.vipOnly != true) }
print("enabled sources: \(enabled.count)")
precondition(!enabled.isEmpty)

func normalizeTitle(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        .replacingOccurrences(of: "[·・:：\\-—_]", with: "", options: .regularExpression)
}

func flexString(_ value: Any?) -> String? {
    switch value {
    case let s as String: return s
    case let n as Int: return String(n)
    case let n as NSNumber: return n.stringValue
    default: return nil
    }
}

func searchSource(_ source: Source, keyword: String) async -> [(String, String, Int)] {
    var base = source.url
    if !base.hasSuffix("/") { base += "/" }
    var components = URLComponents(string: base)!
    components.queryItems = [
        URLQueryItem(name: "ac", value: "list"),
        URLQueryItem(name: "wd", value: keyword),
        URLQueryItem(name: "pg", value: "1"),
    ]
    guard let url = components.url else { return [] }
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
          let http = response as? HTTPURLResponse,
          (200...299).contains(http.statusCode),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let list = json["list"] as? [[String: Any]] else { return [] }

    return list.compactMap { item in
        guard let name = item["vod_name"] as? String,
              let vodId = flexString(item["vod_id"]) else { return nil }
        return (name, vodId, source.id)
    }
}

let keyword = "鲨笼绝境"
var groups: [String: [(String, String, Int)]] = [:]

await withTaskGroup(of: [(String, String, Int)].self) { group in
    for source in enabled {
        group.addTask { await searchSource(source, keyword: keyword) }
    }
    for await batch in group {
        for item in batch {
            let key = normalizeTitle(item.0)
            groups[key, default: []].append(item)
        }
    }
}

print("merged groups: \(groups.count)")
if let first = groups.first {
    print("sample: \(first.key) variants=\(first.value.count)")
}

guard groups.count == 1 else {
    fputs("expected merged total=1, got \(groups.count)\n", stderr)
    exit(2)
}

print("VERIFY PASSED")
