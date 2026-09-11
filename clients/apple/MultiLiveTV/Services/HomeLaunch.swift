import Foundation

struct HomeLaunchPayload {
    let categoryTree: CategoryTree
    let selectedSlug: String?
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

    static func makePayload(
        tree: CategoryTree,
        items: [VodItem],
        page: Int,
        pageCount: Int,
        selectedSlug: String?,
        tvDisplay: Bool
    ) -> HomeLaunchPayload {
        let matched = CategoryMatch.filter(items, selectedSlug: selectedSlug, tree: tree)
        let pool = HomeFeed.replaceFirstPage(pool: [], incoming: matched)
        let displayCount: Int
        if tvDisplay {
            displayCount = HomeFeed.initialAllDisplayCount(allLength: HomeFeed.allItems(pool).count)
        } else {
            displayCount = HomeFeed.initialDisplayCount(poolLength: pool.count)
        }
        return HomeLaunchPayload(
            categoryTree: tree,
            selectedSlug: selectedSlug,
            snapshot: HomeFeedSnapshot(
                pool: pool,
                displayCount: displayCount,
                apiPage: page,
                pageCount: max(pageCount, 1)
            )
        )
    }

    static func load(
        fetchList: (_ slug: String?) async throws -> ListPage,
        tvDisplay: Bool
    ) async throws -> HomeLaunchPayload {
        let tree = UnifiedCategories.tree()
        let slug = CategoryTreeBuilder.defaultSlug(in: tree) ?? UnifiedCategories.defaultSlug
        let page = try await fetchList(slug)
        return makePayload(
            tree: tree,
            items: page.items,
            page: page.page,
            pageCount: page.pageCount,
            selectedSlug: slug,
            tvDisplay: tvDisplay
        )
    }

    static func firstSuccess<T>(
        count: Int,
        operation: @escaping (Int) async throws -> T
    ) async throws -> T {
        guard count > 0 else {
            throw URLError(.resourceUnavailable)
        }
        if count == 1 {
            return try await operation(0)
        }

        var winner: T?
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
                    winner = value
                    group.cancelAll()
                    return
                case .failure(let error):
                    lastError = error
                }
            }
        }
        if let winner {
            return winner
        }
        throw lastError
    }
}
