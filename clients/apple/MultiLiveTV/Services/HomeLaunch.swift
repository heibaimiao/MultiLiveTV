import Foundation

struct HomeLaunchPayload {
    let categoryTree: CategoryTree
    let selectedTypeId: Int?
    let sourceId: Int
    let snapshot: HomeFeedSnapshot
}

enum HomeLaunch {
    struct ListPage {
        let items: [VodItem]
        let page: Int
        let pageCount: Int
    }

    static func shouldEnterMain(didSucceed: Bool) -> Bool {
        didSucceed
    }

    static func childTypeIds(tree: CategoryTree, typeId: Int?) -> [Int] {
        guard let typeId else { return [] }
        return tree.childrenByParent[typeId]?.map(\.typeId) ?? []
    }

    static func makePayload(
        categories: [CategoryDef],
        items: [VodItem],
        page: Int,
        pageCount: Int,
        sourceId: Int,
        tvDisplay: Bool
    ) -> HomeLaunchPayload {
        let tree = CategoryTreeBuilder.build(from: categories)
        let typeId = CategoryTreeBuilder.defaultTypeId(in: tree)
        let matched = CategoryMatch.filter(items, selectedTypeId: typeId, tree: tree)
        let pool = HomeFeed.replaceFirstPage(pool: [], incoming: matched)
        let displayCount: Int
        if tvDisplay {
            displayCount = HomeFeed.initialAllDisplayCount(allLength: HomeFeed.allItems(pool).count)
        } else {
            displayCount = HomeFeed.initialDisplayCount(poolLength: pool.count)
        }
        return HomeLaunchPayload(
            categoryTree: tree,
            selectedTypeId: typeId,
            sourceId: sourceId,
            snapshot: HomeFeedSnapshot(
                pool: pool,
                displayCount: displayCount,
                apiPage: page,
                pageCount: max(pageCount, 1)
            )
        )
    }

    static func load(
        fetchCategories: () async throws -> [CategoryDef],
        fetchList: (_ typeId: Int?, _ childIds: [Int]) async throws -> ListPage,
        sourceId: Int,
        tvDisplay: Bool
    ) async throws -> HomeLaunchPayload {
        let categories = try await fetchCategories()
        let tree = CategoryTreeBuilder.build(from: categories)
        let typeId = CategoryTreeBuilder.defaultTypeId(in: tree)
        let page = try await fetchList(typeId, childTypeIds(tree: tree, typeId: typeId))
        return makePayload(
            categories: categories,
            items: page.items,
            page: page.page,
            pageCount: page.pageCount,
            sourceId: sourceId,
            tvDisplay: tvDisplay
        )
    }

    static func firstSuccess<T>(
        count: Int,
        isAcceptable: @escaping (T) -> Bool = { _ in true },
        operation: @escaping (Int) async throws -> T
    ) async throws -> T {
        guard count > 0 else {
            throw URLError(.resourceUnavailable)
        }
        if count == 1 {
            return try await operation(0)
        }

        var winner: T?
        var fallback: T?
        var lastError: Error = URLError(.cannotConnectToHost)
        await withTaskGroup(of: Result<T, Error>.self) { group in
            for index in 0..<count {
                group.addTask {
                    do {
                        return .success(try await operation(index))
                    } catch {
                        return .failure(error)
                    }
                }
            }

            for _ in 0..<count {
                guard let result = await group.next() else { break }
                switch result {
                case .success(let value):
                    if isAcceptable(value) {
                        winner = value
                        group.cancelAll()
                        return
                    }
                    if fallback == nil {
                        fallback = value
                    }
                case .failure(let error):
                    lastError = error
                }
            }
        }
        if let winner {
            return winner
        }
        if let fallback {
            return fallback
        }
        throw lastError
    }
}
