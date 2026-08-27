import Foundation

@MainActor
final class VodService: ObservableObject {
    private let store: SourceStore

    init() {
        store = (try? SourceStore()) ?? SourceStore(sources: [])
    }

    func fetchTypes(sourceId: Int? = nil) async throws -> TypesResponse {
        let source: Source
        if let sourceId {
            guard let found = store.byID(sourceId) else { throw VodError.sourceNotFound }
            source = found
        } else {
            guard let found = store.default() else { throw VodError.sourceNotFound }
            source = found
        }

        let types = try await MacCMSClient.fetchTypes(source: source)
        let categories = MacCMSCategoryService.buildCategories(from: types)
        return TypesResponse(
            source: ListResponse.SourceRef(id: source.id, name: source.name),
            categories: categories
        )
    }

    func fetchList(page: Int, typeId: Int? = nil, sourceId: Int? = nil) async throws -> ListResponse {
        if let sourceId {
            guard let source = store.byID(sourceId) else { throw VodError.sourceNotFound }
            let result = try await CategoryListService.fetchVodListByTypeMerged(
                store: store,
                source: source,
                typeId: typeId,
                page: page
            )
            return makeListResponse(source: source, typeId: typeId, result: result)
        }

        for source in store.enabled() {
            do {
                let result = try await CategoryListService.fetchVodListByTypeMerged(
                    store: store,
                    source: source,
                    typeId: typeId,
                    page: page
                )
                if !result.list.isEmpty {
                    return makeListResponse(source: source, typeId: typeId, result: result)
                }
            } catch {
                continue
            }
        }

        guard let fallback = store.default() else { throw VodError.sourceNotFound }
        return ListResponse(
            source: ListResponse.SourceRef(id: fallback.id, name: fallback.name),
            typeId: typeId,
            page: page,
            pagecount: 0,
            total: 0,
            list: []
        )
    }

    func search(_ keyword: String, page: Int = 1) async throws -> [VodItem] {
        var mergeable: [MergeableVodItem] = []

        await withTaskGroup(of: [MergeableVodItem].self) { group in
            for source in store.enabled() {
                group.addTask {
                    guard let data = try? await MacCMSClient.search(source: source, keyword: keyword, page: page) else {
                        return []
                    }
                    return data.list.map {
                        MergeableVodItem(item: $0, sourceId: source.id, sourceName: source.name)
                    }
                }
            }
            for await batch in group {
                mergeable.append(contentsOf: batch)
            }
        }

        let merged = VodMergeService.mergeVodItems(mergeable, store: store)
        return VodMergeService.toVodItems(merged)
    }

    func detail(sourceId: Int, vodId: String) async throws -> DetailResponse {
        guard let source = store.byID(sourceId) else { throw VodError.sourceNotFound }
        guard let detail = try await VodMergeService.fetchMergedVodDetail(
            store: store,
            source: source,
            vodId: vodId
        ) else {
            throw VodError.vodNotFound
        }
        return detail
    }

    func parsePlay(sourceId: Int, url: String) async throws -> ParseResponse {
        guard let source = store.byID(sourceId) else { throw VodError.sourceNotFound }
        let response = await PlayParser.parsePlayAddress(source: source, playURL: url)
        if PlaybackSupport.isDirectMediaURL(response.url) {
            return response
        }
        return ParseResponse(url: response.url, parsed: false)
    }

    func source(for id: Int) -> Source? {
        store.byID(id)
    }

    func fetchVodPic(sourceId: Int, vodId: String) async throws -> String? {
        guard let source = store.byID(sourceId) else { throw VodError.sourceNotFound }
        let data = try await MacCMSClient.fetchDetail(source: source, ids: vodId)
        let pic = data.list.first?.vodPic ?? ""
        return pic.isEmpty ? nil : pic
    }

    private func makeListResponse(source: Source, typeId: Int?, result: CategoryListService.ListResult) -> ListResponse {
        ListResponse(
            source: ListResponse.SourceRef(id: source.id, name: source.name),
            typeId: typeId,
            page: result.page,
            pagecount: result.pageCount,
            total: result.total,
            list: VodMergeService.toVodItems(result.list)
        )
    }
}
