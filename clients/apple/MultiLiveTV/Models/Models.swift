import Foundation

struct SourceConnection: Codable, Hashable {
    let endpoint: String
    let searchEndpoint: String?
    let detailEndpoint: String?
    let playEndpoint: String?
    let jxUrl: String?

    enum CodingKeys: String, CodingKey {
        case endpoint
        case searchEndpoint = "search_endpoint"
        case detailEndpoint = "detail_endpoint"
        case playEndpoint = "play_endpoint"
        case jxUrl = "jx_url"
    }

    init(
        endpoint: String,
        searchEndpoint: String? = nil,
        detailEndpoint: String? = nil,
        playEndpoint: String? = nil,
        jxUrl: String? = nil
    ) {
        self.endpoint = endpoint
        self.searchEndpoint = searchEndpoint
        self.detailEndpoint = detailEndpoint
        self.playEndpoint = playEndpoint
        self.jxUrl = jxUrl
    }
}

struct SourceCapabilities: Codable, Hashable {
    let search: Bool
    let category: Bool
    let detail: Bool
    let play: Bool
    let pagination: Bool
    let live: Bool

    static let cmsDefaults = SourceCapabilities(
        search: true,
        category: true,
        detail: true,
        play: true,
        pagination: true,
        live: false
    )

    init(
        search: Bool = true,
        category: Bool = true,
        detail: Bool = true,
        play: Bool = true,
        pagination: Bool = true,
        live: Bool = false
    ) {
        self.search = search
        self.category = category
        self.detail = detail
        self.play = play
        self.pagination = pagination
        self.live = live
    }
}

struct SourceAdapterConfig: Codable, Hashable {
    let type: String
    let parser: String

    static let cmsJSON = SourceAdapterConfig(type: "cms_json", parser: "default_cms_parser")
}

struct SourcePriority: Codable, Hashable {
    let metadataPriority: Int
    let playPriority: Int

    enum CodingKeys: String, CodingKey {
        case metadataPriority = "metadata_priority"
        case playPriority = "play_priority"
    }

    init(metadataPriority: Int, playPriority: Int) {
        self.metadataPriority = metadataPriority
        self.playPriority = playPriority
    }
}

struct Source: Codable, Identifiable, Hashable {
    /// Stable string id, e.g. `cms-143`.
    let sourceId: String
    /// Numeric id used by deep links, unified-categories, and play weights.
    let numericId: Int
    let name: String
    let type: String
    let protocolName: String
    let enabled: Bool
    let inApp: Bool?
    let vipOnly: Bool?
    let connection: SourceConnection
    let capabilities: SourceCapabilities
    let adapter: SourceAdapterConfig
    let priority: SourcePriority

    var id: Int { numericId }

    /// MacCMS / playback base URL (compat).
    var url: String { connection.endpoint }

    /// Parse gateway (compat).
    var jxUrl: String? { connection.jxUrl }

    enum CodingKeys: String, CodingKey {
        case sourceId = "source_id"
        case numericId
        case name, type
        case protocolName = "protocol"
        case enabled, inApp
        case vipOnly = "vip_only"
        case connection, capabilities, adapter, priority
    }

    init(
        sourceId: String,
        numericId: Int,
        name: String,
        type: String = "cms",
        protocolName: String = "json",
        enabled: Bool = true,
        inApp: Bool? = true,
        vipOnly: Bool? = false,
        connection: SourceConnection,
        capabilities: SourceCapabilities = .cmsDefaults,
        adapter: SourceAdapterConfig = .cmsJSON,
        priority: SourcePriority = SourcePriority(metadataPriority: 100, playPriority: 100)
    ) {
        self.sourceId = sourceId
        self.numericId = numericId
        self.name = name
        self.type = type
        self.protocolName = protocolName
        self.enabled = enabled
        self.inApp = inApp
        self.vipOnly = vipOnly
        self.connection = connection
        self.capabilities = capabilities
        self.adapter = adapter
        self.priority = priority
    }

    /// Test / migration helper matching the legacy flat shape.
    init(
        id: Int,
        name: String,
        url: String,
        flag: Int = 0,
        jxUrl: String? = nil,
        vipOnly: Bool? = false,
        capabilities: SourceCapabilities = .cmsDefaults,
        metadataPriority: Int = 100,
        playPriority: Int = 100
    ) {
        self.init(
            sourceId: "cms-\(id)",
            numericId: id,
            name: name,
            type: "cms",
            protocolName: "json",
            enabled: flag == 0,
            inApp: true,
            vipOnly: vipOnly,
            connection: SourceConnection(endpoint: url, jxUrl: jxUrl),
            capabilities: capabilities,
            adapter: .cmsJSON,
            priority: SourcePriority(metadataPriority: metadataPriority, playPriority: playPriority)
        )
    }
}

struct SourceRegistryDocument: Codable {
    let version: Int
    let sources: [Source]
}

struct VodVariant: Codable, Hashable {
    let sourceId: Int
    let sourceName: String
    let vodId: String
}

struct VodItem: Codable, Identifiable, Hashable {
    /// Stable across sources: raw `vodId` alone collides between sites and breaks SwiftUI lists.
    var id: String {
        if let primarySourceId {
            return "\(primarySourceId):\(vodId)"
        }
        if let first = variants?.first {
            return "\(first.sourceId):\(vodId)"
        }
        return "x:\(vodId):\(vodName)"
    }
    let vodId: String
    let vodName: String
    let vodPic: String
    let vodRemarks: String?
    let vodBlurb: String?
    let vodContent: String?
    let typeName: String?
    let vodClass: String?
    let vodYear: String?
    let variants: [VodVariant]?
    let primarySourceId: Int?
    let vodTime: Int

    enum CodingKeys: String, CodingKey {
        case vodId = "vod_id"
        case vodName = "vod_name"
        case vodPic = "vod_pic"
        case vodRemarks = "vod_remarks"
        case vodBlurb = "vod_blurb"
        case vodContent = "vod_content"
        case typeName = "type_name"
        case vodClass = "vod_class"
        case vodYear = "vod_year"
        case variants
        case primarySourceId
        case vodTime = "vod_time"
    }

    var resolvedSourceId: Int {
        primarySourceId ?? variants?.first?.sourceId ?? 33
    }

    var displayBlurb: String? {
        let text = (vodContent?.isEmpty == false ? vodContent : vodBlurb) ?? ""
        return VodDisplayFormatter.plainText(text)
    }

    var displayRemarks: String? {
        VodDisplayFormatter.formatRemarks(vodRemarks)
    }

    var displayGenreLine: String? {
        VodDisplayFormatter.genreLine(typeName: typeName, year: vodYear)
    }

    init(
        vodId: String,
        vodName: String,
        vodPic: String,
        vodRemarks: String? = nil,
        vodBlurb: String? = nil,
        vodContent: String? = nil,
        typeName: String? = nil,
        vodClass: String? = nil,
        vodYear: String? = nil,
        variants: [VodVariant]? = nil,
        primarySourceId: Int? = nil,
        vodTime: Int = 0
    ) {
        self.vodId = vodId
        self.vodName = vodName
        self.vodPic = vodPic
        self.vodRemarks = vodRemarks
        self.vodBlurb = vodBlurb
        self.vodContent = vodContent
        self.typeName = typeName
        self.vodClass = vodClass
        self.vodYear = vodYear
        self.variants = variants
        self.primarySourceId = primarySourceId
        self.vodTime = vodTime
    }

}

struct CategoryDef: Codable, Identifiable, Hashable {
    var id: Int { typeId }
    let typeId: Int
    let label: String
}

struct Episode: Codable, Identifiable, Hashable {
    var id: String { url }
    let name: String
    let url: String
}

struct PlaySource: Codable, Identifiable, Hashable {
    var id: String { key }
    let name: String
    let key: String
    let episodes: [Episode]
    let sourceId: Int?
    let weight: Int
    let mode: String
    let playFrom: String?
    let providerId: String?
    let ticket: String?
    let requiresAuth: Bool

    init(
        name: String,
        key: String,
        episodes: [Episode],
        sourceId: Int? = nil,
        weight: Int = 0,
        mode: String = "direct",
        playFrom: String? = nil,
        providerId: String? = nil,
        ticket: String? = nil,
        requiresAuth: Bool = false
    ) {
        self.name = name
        self.key = key
        self.episodes = episodes
        self.sourceId = sourceId
        self.weight = weight
        self.mode = mode
        self.playFrom = playFrom
        self.providerId = providerId
        self.ticket = ticket
        self.requiresAuth = requiresAuth
    }

    enum CodingKeys: String, CodingKey {
        case name, key, episodes, sourceId, weight, mode, playFrom, providerId, ticket, requiresAuth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        key = try container.decode(String.self, forKey: .key)
        episodes = try container.decode([Episode].self, forKey: .episodes)
        sourceId = try container.decodeIfPresent(Int.self, forKey: .sourceId)
        weight = try container.decodeIfPresent(Int.self, forKey: .weight) ?? 0
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "direct"
        playFrom = try container.decodeIfPresent(String.self, forKey: .playFrom)
        providerId = try container.decodeIfPresent(String.self, forKey: .providerId)
        ticket = try container.decodeIfPresent(String.self, forKey: .ticket)
        requiresAuth = try container.decodeIfPresent(Bool.self, forKey: .requiresAuth) ?? false
    }
}

struct ListResponse: Codable {
    let source: SourceRef?
    let typeId: Int?
    let page: Int
    let pagecount: Int
    let total: Int
    let list: [VodItem]

    struct SourceRef: Codable {
        let id: Int
        let name: String
    }
}

struct TypesResponse: Codable {
    let source: ListResponse.SourceRef
    let categories: [CategoryDef]
}

struct SearchResponse: Codable {
    let keyword: String
    let merged: Bool
    let total: Int
    let list: [VodItem]
}

struct DetailResponse: Codable {
    let vod: VodItem
    let playSources: [PlaySource]
    let variants: [VodVariant]
    let merged: Bool
}

struct ParseResponse: Codable {
    let url: String
    let parsed: Bool
    let mode: String?
    let expiresAt: Int64?

    init(url: String, parsed: Bool, mode: String? = "direct", expiresAt: Int64? = nil) {
        self.url = url
        self.parsed = parsed
        self.mode = mode
        self.expiresAt = expiresAt
    }
}

