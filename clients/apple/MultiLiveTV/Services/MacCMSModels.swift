import Foundation

struct VodTypeRaw: Decodable {
    let typeId: Int
    let typeName: String

    enum CodingKeys: String, CodingKey {
        case typeId = "type_id"
        case typeName = "type_name"
    }
}

struct VodItemRaw {
    let vodId: String
    let vodName: String
    let vodPic: String
    let vodRemarks: String
    let vodYear: String
    let vodArea: String
    let vodClass: String
    let vodBlurb: String
    let vodContent: String
    let vodPlayFrom: String
    let vodPlayURL: String
    let typeId: Int
    let typeName: String
    let vodTime: Int

    func toVodItem(variants: [VodVariant]? = nil, primarySourceId: Int? = nil) -> VodItem {
        VodItem(
            vodId: vodId,
            vodName: vodName,
            vodPic: vodPic,
            vodRemarks: vodRemarks.isEmpty ? nil : vodRemarks,
            vodBlurb: vodBlurb.isEmpty ? nil : vodBlurb,
            vodContent: vodContent.isEmpty ? nil : vodContent,
            typeName: typeName.isEmpty ? nil : typeName,
            vodClass: vodClass.isEmpty ? nil : vodClass,
            variants: variants,
            primarySourceId: primarySourceId,
            vodTime: vodTime
        )
    }
}

struct MacCMSListResponse {
    let code: Int
    let msg: String
    let page: Int
    let pageCount: Int
    let limit: String
    let total: Int
    let list: [VodItemRaw]
    let types: [VodTypeRaw]
}

struct MacCMSDetailResponse {
    let code: Int
    let msg: String
    let list: [VodItemRaw]
}

struct MergeableVodItem {
    let item: VodItemRaw
    let sourceId: Int
    let sourceName: String
}

enum MacCMSJSONParser {
    static func parseList(_ data: Data) throws -> MacCMSListResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid json"))
        }
        let list = parseVodItems(json["list"])
        let types = parseTypes(json["class"])
        return MacCMSListResponse(
            code: flexInt(json["code"]) ?? 0,
            msg: json["msg"] as? String ?? "",
            page: flexInt(json["page"]) ?? 1,
            pageCount: flexInt(json["pagecount"]) ?? 1,
            limit: flexString(json["limit"]) ?? "",
            total: flexInt(json["total"]) ?? 0,
            list: list,
            types: types
        )
    }

    static func parseDetail(_ data: Data) throws -> MacCMSDetailResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid json"))
        }
        return MacCMSDetailResponse(
            code: flexInt(json["code"]) ?? 0,
            msg: json["msg"] as? String ?? "",
            list: parseVodItems(json["list"])
        )
    }

    private static func parseVodItems(_ value: Any?) -> [VodItemRaw] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap(parseVodItem)
    }

    private static func parseTypes(_ value: Any?) -> [VodTypeRaw] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let typeId = flexInt(dict["type_id"]),
                  let typeName = dict["type_name"] as? String else { return nil }
            return VodTypeRaw(typeId: typeId, typeName: typeName)
        }
    }

    private static func parseVodItem(_ dict: [String: Any]) -> VodItemRaw? {
        guard let vodName = dict["vod_name"] as? String else { return nil }
        let vodId = flexString(dict["vod_id"]) ?? ""
        let vodTime = parseVodTime(dict["vod_time"])
        let vodTimeAdd = parseVodTime(dict["vod_time_add"])
        return VodItemRaw(
            vodId: vodId,
            vodName: vodName,
            vodPic: dict["vod_pic"] as? String ?? "",
            vodRemarks: dict["vod_remarks"] as? String ?? "",
            vodYear: dict["vod_year"] as? String ?? "",
            vodArea: dict["vod_area"] as? String ?? "",
            vodClass: dict["vod_class"] as? String ?? "",
            vodBlurb: dict["vod_blurb"] as? String ?? "",
            vodContent: dict["vod_content"] as? String ?? "",
            vodPlayFrom: dict["vod_play_from"] as? String ?? "",
            vodPlayURL: dict["vod_play_url"] as? String ?? "",
            typeId: flexInt(dict["type_id"]) ?? 0,
            typeName: dict["type_name"] as? String ?? "",
            vodTime: vodTime > 0 ? vodTime : vodTimeAdd
        )
    }

    static func parseVodTime(_ value: Any?) -> Int {
        switch value {
        case let n as Int:
            return normalizeUnix(n)
        case let n as Double:
            return normalizeUnix(Int(n))
        case let n as NSNumber:
            return normalizeUnix(n.intValue)
        case let s as String:
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return 0 }
            if let n = Int(trimmed) { return normalizeUnix(n) }
            return parseDateTimeString(trimmed)
        default:
            return 0
        }
    }

    private static func normalizeUnix(_ value: Int) -> Int {
        if value <= 0 { return 0 }
        if value > 10_000_000_000 { return value / 1000 }
        return value
    }

    private static func parseDateTimeString(_ raw: String) -> Int {
        let parts = raw.split { !$0.isNumber }.compactMap { Int($0) }
        guard parts.count >= 3 else { return 0 }

        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.hour = parts.count > 3 ? parts[3] : 0
        comps.minute = parts.count > 4 ? parts[4] : 0
        comps.second = parts.count > 5 ? parts[5] : 0

        guard let date = comps.date else { return 0 }
        return Int(date.timeIntervalSince1970)
    }

    private static func flexString(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let n as Int: return String(n)
        case let n as Double: return String(Int(n))
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    private static func flexInt(_ value: Any?) -> Int? {
        switch value {
        case let n as Int: return n
        case let n as Double: return Int(n)
        case let s as String: return Int(s)
        case let n as NSNumber: return n.intValue
        default: return nil
        }
    }
}
