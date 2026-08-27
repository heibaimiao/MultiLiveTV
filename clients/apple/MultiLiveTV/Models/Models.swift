import Foundation

struct Source: Codable, Identifiable, Hashable {
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
    let vodBlurb: String?
    let vodContent: String?
    let typeName: String?
    let variants: [VodVariant]?
    let primarySourceId: Int?

    enum CodingKeys: String, CodingKey {
        case vodId = "vod_id"
        case vodName = "vod_name"
        case vodPic = "vod_pic"
        case vodRemarks = "vod_remarks"
        case vodBlurb = "vod_blurb"
        case vodContent = "vod_content"
        case typeName = "type_name"
        case variants
        case primarySourceId
    }

    var resolvedSourceId: Int {
        primarySourceId ?? variants?.first?.sourceId ?? 33
    }

    var displayBlurb: String? {
        let text = (vodContent?.isEmpty == false ? vodContent : vodBlurb) ?? ""
        return text.isEmpty ? nil : text
    }

    var displayRemarks: String? {
        VodDisplayFormatter.formatRemarks(vodRemarks)
    }

    init(
        vodId: String,
        vodName: String,
        vodPic: String,
        vodRemarks: String? = nil,
        vodBlurb: String? = nil,
        vodContent: String? = nil,
        typeName: String? = nil,
        variants: [VodVariant]? = nil,
        primarySourceId: Int? = nil
    ) {
        self.vodId = vodId
        self.vodName = vodName
        self.vodPic = vodPic
        self.vodRemarks = vodRemarks
        self.vodBlurb = vodBlurb
        self.vodContent = vodContent
        self.typeName = typeName
        self.variants = variants
        self.primarySourceId = primarySourceId
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

