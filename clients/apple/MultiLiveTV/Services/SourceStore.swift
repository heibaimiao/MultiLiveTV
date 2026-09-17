import Foundation

final class SourceStore {
    private let sources: [Source]
    private let byNumericId: [Int: Source]
    private let bySourceIdKey: [String: Source]

    init(bundle: Bundle = .main) throws {
        let document = try Self.loadRegistry(bundle: bundle)
        sources = document.sources
        byNumericId = Self.uniqueIndex(sources, key: \.numericId)
        bySourceIdKey = Self.uniqueIndex(sources, key: \.sourceId)
    }

    init(sources: [Source]) {
        self.sources = sources
        byNumericId = Self.uniqueIndex(sources, key: \.numericId)
        bySourceIdKey = Self.uniqueIndex(sources, key: \.sourceId)
    }

    private static func uniqueIndex<Key: Hashable>(
        _ sources: [Source],
        key: KeyPath<Source, Key>
    ) -> [Key: Source] {
        Dictionary(sources.map { ($0[keyPath: key], $0) }, uniquingKeysWith: { _, last in last })
    }

    func all() -> [Source] { sources }

    /// Configured entry regardless of enabled (deep link / diagnostics).
    func configured(id numericId: Int) -> Source? {
        byNumericId[numericId]
    }

    func configured(sourceId: String) -> Source? {
        bySourceIdKey[sourceId]
    }

    /// Admin-enabled and not vip-gated — may still be unhealthy.
    func enabled() -> [Source] {
        sources.filter { $0.enabled && ($0.vipOnly != true) }
    }

    /// Enabled sources that may be used for a given capability.
    func collectable(capability: KeyPath<SourceCapabilities, Bool>) -> [Source] {
        enabled().filter { $0.capabilities[keyPath: capability] }
    }

    /// Collectable by numeric id; nil when disabled / missing / vip.
    func byID(_ id: Int) -> Source? {
        guard let source = byNumericId[id], source.enabled, source.vipOnly != true else {
            return nil
        }
        return source
    }

    func bySourceID(_ sourceId: String) -> Source? {
        guard let source = bySourceIdKey[sourceId], source.enabled, source.vipOnly != true else {
            return nil
        }
        return source
    }

    func `default`() -> Source? {
        enabled().first
    }

    func metadataPriority(for numericId: Int) -> Int {
        configured(id: numericId)?.priority.metadataPriority ?? 100
    }

    func playPriority(for numericId: Int) -> Int {
        configured(id: numericId)?.priority.playPriority ?? 100
    }

    private static func loadRegistry(bundle: Bundle) throws -> SourceRegistryDocument {
        if let url = bundle.url(forResource: "source-registry", withExtension: "json") {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SourceRegistryDocument.self, from: data)
        }
        // Legacy fallback for older bundles / tests without registry resource.
        guard let url = bundle.url(forResource: "sources", withExtension: "json") else {
            throw VodError.missingSources
        }
        let data = try Data(contentsOf: url)
        let legacy = try JSONDecoder().decode([LegacySource].self, from: data)
        return SourceRegistryDocument(
            version: 0,
            sources: legacy.map { $0.toSource() }
        )
    }
}

private struct LegacySource: Codable {
    let id: Int
    let name: String
    let url: String
    let flag: Int
    let jxUrl: String?
    let vipOnly: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, url, flag
        case jxUrl = "jx_url"
        case vipOnly = "vip_only"
    }

    func toSource() -> Source {
        Source(
            id: id,
            name: name,
            url: url,
            flag: flag,
            jxUrl: jxUrl,
            vipOnly: vipOnly
        )
    }
}

enum VodError: LocalizedError {
    case missingSources
    case sourceNotFound
    case vodNotFound

    var errorDescription: String? {
        switch self {
        case .missingSources: return "未找到 source-registry.json"
        case .sourceNotFound: return "资源站不存在"
        case .vodNotFound: return "未找到影片"
        }
    }
}
