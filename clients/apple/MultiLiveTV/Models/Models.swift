import Foundation

struct Source: Codable, Identifiable, Hashable {
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

struct VodVariant: Codable, Hashable {
    let sourceId: Int
    let sourceName: String
    let vodId: String
}

struct VodItem: Codable, Identifiable, Hashable {
    var id: String { vodId }
    let vodId: String
    let vodName: String
    let vodPic: String
    let vodRemarks: String?
    let typeName: String?
    let variants: [VodVariant]?
    let primarySourceId: Int?

    enum CodingKeys: String, CodingKey {
        case vodId = "vod_id"
        case vodName = "vod_name"
        case vodPic = "vod_pic"
        case vodRemarks = "vod_remarks"
        case typeName = "type_name"
        case variants
        case primarySourceId
    }

    var resolvedSourceId: Int {
        primarySourceId ?? variants?.first?.sourceId ?? 33
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
}

struct TokenPair: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct Favorite: Codable, Identifiable {
    let id: String
    let mergeKey: String
    let vodName: String
    let primarySourceId: Int
    let primaryVodId: String
    let poster: String?

    enum CodingKeys: String, CodingKey {
        case id
        case mergeKey = "merge_key"
        case vodName = "vod_name"
        case primarySourceId = "primary_source_id"
        case primaryVodId = "primary_vod_id"
        case poster
    }
}

struct WatchProgress: Codable, Identifiable {
    let id: String
    let progressKey: String
    let positionSec: Double
    let durationSec: Double

    enum CodingKeys: String, CodingKey {
        case id
        case progressKey = "progress_key"
        case positionSec = "position_sec"
        case durationSec = "duration_sec"
    }
}
