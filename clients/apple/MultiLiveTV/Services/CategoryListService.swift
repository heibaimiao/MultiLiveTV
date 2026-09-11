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

    static func isHiddenCategoryLabel(_ text: String) -> Bool {
        text.contains("伦理") || text.contains("倫理")
    }

    static func isTypeVisible(_ typeName: String) -> Bool {
        if typeName.contains("[关]") { return false }
        if typeName.range(of: "x$", options: [.regularExpression, .caseInsensitive]) != nil { return false }
        if isHiddenCategoryLabel(typeName) { return false }
        return true
    }

    static func isItemVisible(_ item: VodItem) -> Bool {
        if let typeName = item.typeName, !typeName.isEmpty, isHiddenCategoryLabel(typeName) {
            return false
        }
        if let vodClass = item.vodClass, !vodClass.isEmpty, isHiddenCategoryLabel(vodClass) {
            return false
        }
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

    struct ChildListPage {
        let childId: Int
        let list: [VodItemRaw]
        let pageCount: Int
        let total: Int
    }

    struct FlattenedChildPages {
        let items: [VodItemRaw]
        let pageCount: Int
        let total: Int
    }

    static func shouldFetchChildrenDirectly(knownChildTypeIds: [Int]) -> Bool {
        !knownChildTypeIds.isEmpty
    }

    static func flattenChildPages(_ pages: [ChildListPage], orderedChildIds: [Int]) -> FlattenedChildPages {
        let byId = Dictionary(pages.map { ($0.childId, $0) }, uniquingKeysWith: { first, _ in first })
        var items: [VodItemRaw] = []
        var pageCount = 1
        var total = 0
        for childId in orderedChildIds {
            guard let page = byId[childId] else { continue }
            items.append(contentsOf: page.list)
            pageCount = max(pageCount, page.pageCount)
            total += page.total
        }
        return FlattenedChildPages(items: items, pageCount: pageCount, total: total)
    }

    static func fetchVodListByTypeMerged(
        store: SourceStore,
        source: Source,
        typeId: Int?,
        page: Int,
        knownChildTypeIds: [Int] = [],
        hours: Int? = nil
    ) async throws -> ListResult {
        if typeId == nil {
            let data = try await SourceCollector.list(source: source, page: page, typeId: nil, hours: hours)
            let items = data.list.map { $0.toVodItemRaw() }
            return ListResult(
                code: 1,
                msg: "ok",
                page: data.page,
                pageCount: data.pageCount,
                limit: String(items.count),
                total: data.total,
                list: mergeListItems(store: store, source: source, items: items)
            )
        }

        if shouldFetchChildrenDirectly(knownChildTypeIds: knownChildTypeIds) {
            return await fetchMergedChildLists(
                store: store,
                source: source,
                page: page,
                childIds: knownChildTypeIds,
                hours: hours
            )
        }

        let direct = try await SourceCollector.list(source: source, page: page, typeId: typeId, hours: hours)
        let directItems = direct.list.map { $0.toVodItemRaw() }
        if !directItems.isEmpty || direct.total > 0 {
            return ListResult(
                code: 1,
                msg: "ok",
                page: direct.page,
                pageCount: direct.pageCount,
                limit: String(directItems.count),
                total: direct.total,
                list: mergeListItems(store: store, source: source, items: directItems)
            )
        }

        let types = try await SourceCollector.fetchTypes(source: source)
        let childIds = MacCMSCategoryService.getChildTypeIds(types: types, parentId: typeId!)
        if childIds.isEmpty {
            return ListResult(
                code: 1,
                msg: "ok",
                page: direct.page,
                pageCount: direct.pageCount,
                limit: String(directItems.count),
                total: direct.total,
                list: mergeListItems(store: store, source: source, items: directItems)
            )
        }

        return await fetchMergedChildLists(
            store: store,
            source: source,
            page: page,
            childIds: childIds,
            hours: hours
        )
    }

    private static func fetchMergedChildLists(
        store: SourceStore,
        source: Source,
        page: Int,
        childIds: [Int],
        hours: Int? = nil
    ) async -> ListResult {
        let pages: [ChildListPage] = await withTaskGroup(of: ChildListPage?.self) { group in
            for childId in childIds {
                group.addTask {
                    guard let data = try? await SourceCollector.list(
                        source: source,
                        page: page,
                        typeId: childId,
                        hours: hours
                    ) else {
                        return nil
                    }
                    return ChildListPage(
                        childId: childId,
                        list: data.list.map { $0.toVodItemRaw() },
                        pageCount: data.pageCount,
                        total: data.total
                    )
                }
            }
            var collected: [ChildListPage] = []
            collected.reserveCapacity(childIds.count)
            for await childPage in group {
                if let childPage { collected.append(childPage) }
            }
            return collected
        }

        let flattened = flattenChildPages(pages, orderedChildIds: childIds)
        let list = mergeListItems(store: store, source: source, items: flattened.items)
        return ListResult(
            code: 1,
            msg: "ok",
            page: page,
            pageCount: flattened.pageCount,
            limit: String(list.count),
            total: flattened.total,
            list: list
        )
    }

    private static let maxFanout = 8

    /// 统一分类：按 slug 映射多源并行拉取并合并。slug == nil 时拉各源「最新」页。
    /// - Parameter hours: MacCMS `h`，最近 N 小时内更新；nil / ≤0 不传。
    static func fetchUnifiedList(
        store: SourceStore,
        slug: String?,
        page: Int,
        hours: Int? = nil
    ) async throws -> ListResult {
        let enabled = store.collectable(capability: \.category)
        guard !enabled.isEmpty else {
            throw URLError(.resourceUnavailable)
        }

        let jobs: [(source: Source, typeId: Int?)]
        if let slug {
            let enabledIds = Set(enabled.map(\.id))
            let mappings = UnifiedCategories.mappings(for: slug)
                .filter { enabledIds.contains($0.sourceId) }
            jobs = mappings.compactMap { mapping in
                guard let source = store.byID(mapping.sourceId) else { return nil }
                return (source, Optional(mapping.typeId))
            }
            .sorted {
                store.metadataPriority(for: $0.source.id) > store.metadataPriority(for: $1.source.id)
            }
            if jobs.isEmpty {
                return ListResult(
                    code: 1,
                    msg: "ok",
                    page: page,
                    pageCount: 1,
                    limit: "0",
                    total: 0,
                    list: []
                )
            }
        } else {
            jobs = enabled
                .sorted {
                    store.metadataPriority(for: $0.id) > store.metadataPriority(for: $1.id)
                }
                .map { ($0, nil) }
        }

        // Try higher-priority sources first, but keep a wide pool so one flaky tier
        // cannot shrink the home/category grid to a handful of posters.
        let limited = Array(jobs.prefix(max(maxFanout * 4, maxFanout)))
        var mergeable: [MergeableVodItem] = []
        var pageCount = 1
        var total = 0

        await withTaskGroup(of: (items: [MergeableVodItem], pageCount: Int, total: Int)?.self) { group in
            var inFlight = 0
            var index = 0
            func enqueue() {
                while inFlight < maxFanout, index < limited.count {
                    let job = limited[index]
                    index += 1
                    inFlight += 1
                    group.addTask {
                        guard let data = try? await SourceCollector.list(
                            source: job.source,
                            page: page,
                            typeId: job.typeId,
                            hours: hours
                        ), !data.list.isEmpty else {
                            return nil
                        }
                        let items = data.list.map {
                            MergeableVodItem(
                                item: $0.toVodItemRaw(),
                                sourceId: job.source.id,
                                sourceName: job.source.name
                            )
                        }
                        return (items, data.pageCount, data.total)
                    }
                }
            }
            enqueue()
            for await result in group {
                inFlight -= 1
                if let result {
                    mergeable.append(contentsOf: result.items)
                    pageCount = max(pageCount, result.pageCount)
                    total += result.total
                }
                enqueue()
            }
        }

        let list = VodMergeService.sortMergedByUpdatedDesc(
            VodMergeService.mergeVodItems(mergeable, store: store)
        )
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
