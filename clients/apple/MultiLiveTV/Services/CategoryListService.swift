import Foundation

enum MacCMSCategoryService {
    private static let typeAliases: [String: String] = [
        "日本剧": "日剧", "韩国剧": "韩剧", "泰国剧": "泰剧", "台湾剧": "台剧",
        "香港剧": "港剧", "大陆剧": "国产剧", "记录片": "纪录片", "日本动漫": "日韩动漫",
        "连续剧": "剧集", "电影片": "电影", "综艺片": "综艺", "动漫片": "动漫",
    ]

    private static let parentNames: Set<String> = ["电影", "剧集", "综艺", "动漫"]

    static func normalizeTypeName(_ typeName: String) -> String {
        var cleaned = typeName
            .replacingOccurrences(of: "\\[关\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.range(of: "x$", options: [.regularExpression, .caseInsensitive]) != nil {
            cleaned = String(cleaned.dropLast())
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return typeAliases[cleaned] ?? cleaned
    }

    static func isTypeVisible(_ typeName: String) -> Bool {
        if typeName.contains("[关]") { return false }
        if typeName.range(of: "x$", options: [.regularExpression, .caseInsensitive]) != nil { return false }
        return true
    }

    static func filterVisibleTypes(_ types: [VodTypeRaw]) -> [VodTypeRaw] {
        types.filter { isTypeVisible($0.typeName) }
    }

    static func buildCategories(from types: [VodTypeRaw]) -> [CategoryDef] {
        filterVisibleTypes(types).map {
            CategoryDef(typeId: $0.typeId, label: normalizeTypeName($0.typeName))
        }
    }

    static func getChildTypeIds(types: [VodTypeRaw], parentId: Int) -> [Int] {
        guard let parent = types.first(where: { $0.typeId == parentId }),
              parentNames.contains(normalizeTypeName(parent.typeName)) else { return [] }

        let parentName = normalizeTypeName(parent.typeName)
        let visible = filterVisibleTypes(types)
        let candidates = visible.filter {
            $0.typeId != parentId && !parentNames.contains(normalizeTypeName($0.typeName))
        }

        let matcher: (String) -> Bool
        switch parentName {
        case "电影":
            matcher = { name in
                (name.hasSuffix("片") || name == "纪录片") && !name.contains("动漫") && !name.contains("动画")
            }
        case "剧集":
            matcher = { name in name.hasSuffix("剧") && name != "短剧" }
        case "综艺":
            matcher = { name in name.contains("综艺") }
        case "动漫":
            matcher = { name in name.contains("动漫") || name.contains("动画") }
        default:
            return []
        }

        return candidates
            .filter { matcher(normalizeTypeName($0.typeName)) }
            .map(\.typeId)
    }
}

enum CategoryListService {
    struct ListResult {
        let code: Int
        let msg: String
        let page: Int
        let pageCount: Int
        let limit: String
        let total: Int
        let list: [VodMergeService.MergedVodItem]
    }

    static func fetchVodListByTypeMerged(
        store: SourceStore,
        source: Source,
        typeId: Int?,
        page: Int
    ) async throws -> ListResult {
        if typeId == nil {
            let data = try await MacCMSClient.fetchList(source: source, page: page, typeId: nil)
            return ListResult(
                code: data.code,
                msg: data.msg,
                page: data.page,
                pageCount: data.pageCount,
                limit: data.limit,
                total: data.total,
                list: mergeListItems(store: store, source: source, items: data.list)
            )
        }

        let direct = try await MacCMSClient.fetchList(source: source, page: page, typeId: typeId)
        if !direct.list.isEmpty || direct.total > 0 {
            return ListResult(
                code: direct.code,
                msg: direct.msg,
                page: direct.page,
                pageCount: direct.pageCount,
                limit: direct.limit,
                total: direct.total,
                list: mergeListItems(store: store, source: source, items: direct.list)
            )
        }

        let types = try await MacCMSClient.fetchTypes(source: source)
        let childIds = MacCMSCategoryService.getChildTypeIds(types: types, parentId: typeId!)
        if childIds.isEmpty {
            return ListResult(
                code: direct.code,
                msg: direct.msg,
                page: direct.page,
                pageCount: direct.pageCount,
                limit: direct.limit,
                total: direct.total,
                list: mergeListItems(store: store, source: source, items: direct.list)
            )
        }

        var allItems: [VodItemRaw] = []
        var pageCount = 1
        var total = 0
        for childId in childIds {
            guard let data = try? await MacCMSClient.fetchList(source: source, page: page, typeId: childId) else {
                continue
            }
            allItems.append(contentsOf: data.list)
            pageCount = max(pageCount, data.pageCount)
            total += data.total
        }

        let list = mergeListItems(store: store, source: source, items: allItems)
        return ListResult(
            code: 1,
            msg: "ok",
            page: page,
            pageCount: pageCount,
            limit: String(list.count),
            total: total,
            list: list
        )
    }

    private static func mergeListItems(store: SourceStore, source: Source, items: [VodItemRaw]) -> [VodMergeService.MergedVodItem] {
        let mergeable = items.map {
            MergeableVodItem(item: $0, sourceId: source.id, sourceName: source.name)
        }
        return VodMergeService.mergeVodItems(mergeable, store: store)
    }
}
