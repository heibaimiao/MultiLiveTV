import Foundation

enum HomeFeed {
    static let fetchSize = 50
    static let initialDisplay = 30
    static let scrollLoadSize = 20
    static let hotSize = 6
    static let recentSize = 6
    static let allRowSize = 6

    enum ContentPhase: Equatable {
        case loading
        case error(String)
        case empty
        case content
    }

    enum LoadMoreAction: Equatable {
        case reveal(displayCount: Int)
        case fetch(page: Int)
        case idle
    }

    static func normalizeTitle(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[·・:：\\-—_]", with: "", options: .regularExpression)
    }

    static func mergeKey(for item: VodItem) -> String {
        normalizeTitle(item.vodName)
    }

    static func initialDisplayCount(poolLength: Int) -> Int {
        min(initialDisplay, poolLength)
    }

    static func nextDisplayCount(current: Int, poolLength: Int) -> Int {
        min(current + scrollLoadSize, poolLength)
    }

    static func canLoadMore(displayCount: Int, poolLength: Int, apiPage: Int, pageCount: Int) -> Bool {
        displayCount < poolLength || apiPage < pageCount
    }

    static func canLoadMorePages(apiPage: Int, pageCount: Int) -> Bool {
        apiPage < pageCount
    }

    static func hotItems(_ pool: [VodItem]) -> [VodItem] {
        Array(pool.prefix(hotSize))
    }

    static func recentItems(_ pool: [VodItem]) -> [VodItem] {
        Array(sortedRest(pool).prefix(recentSize))
    }

    static func allItems(_ pool: [VodItem]) -> [VodItem] {
        Array(sortedRest(pool).dropFirst(recentSize))
    }

    static func allRows(items: [VodItem], displayCount: Int) -> [[VodItem]] {
        let visible = Array(items.prefix(max(displayCount, 0)))
        guard !visible.isEmpty else { return [] }
        return stride(from: 0, to: visible.count, by: allRowSize).map { start in
            Array(visible[start..<min(start + allRowSize, visible.count)])
        }
    }

    static func initialAllDisplayCount(allLength: Int) -> Int {
        min(allRowSize, max(allLength, 0))
    }

    static func nextAllDisplayCount(current: Int, allLength: Int) -> Int {
        min(current + allRowSize, max(allLength, 0))
    }

    static func canLoadMoreAll(displayCount: Int, allLength: Int, apiPage: Int, pageCount: Int) -> Bool {
        displayCount < allLength || apiPage < pageCount
    }

    static func nextAllLoadMore(
        displayCount: Int,
        allLength: Int,
        apiPage: Int,
        pageCount: Int,
        isBusy: Bool
    ) -> LoadMoreAction {
        if isBusy { return .idle }
        if displayCount < allLength {
            return .reveal(displayCount: nextAllDisplayCount(current: displayCount, allLength: allLength))
        }
        if apiPage < pageCount {
            return .fetch(page: apiPage + 1)
        }
        return .idle
    }

    static func shouldPrefetchMore(index: Int, itemCount: Int) -> Bool {
        itemCount > 0 && index >= max(itemCount - 2, 0)
    }

    static func nextPageLoadMore(apiPage: Int, pageCount: Int, isBusy: Bool) -> LoadMoreAction {
        if isBusy { return .idle }
        if apiPage < pageCount { return .fetch(page: apiPage + 1) }
        return .idle
    }

    private static func sortedRest(_ pool: [VodItem]) -> [VodItem] {
        Array(pool.dropFirst(hotSize))
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.vodTime != rhs.element.vodTime {
                    return lhs.element.vodTime > rhs.element.vodTime
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func contentPhase(isLoading: Bool, errorMessage: String?, poolIsEmpty: Bool) -> ContentPhase {
        if isLoading && poolIsEmpty { return .loading }
        if let errorMessage, poolIsEmpty { return .error(errorMessage) }
        if poolIsEmpty { return .empty }
        return .content
    }

    static func nextLoadMore(
        displayCount: Int,
        poolLength: Int,
        apiPage: Int,
        pageCount: Int,
        isBusy: Bool
    ) -> LoadMoreAction {
        if isBusy { return .idle }
        if displayCount < poolLength {
            return .reveal(displayCount: nextDisplayCount(current: displayCount, poolLength: poolLength))
        }
        if apiPage < pageCount {
            return .fetch(page: apiPage + 1)
        }
        return .idle
    }

    static func loadMoreFooterID(displayCount: Int, poolLength: Int, apiPage: Int) -> String {
        "\(displayCount)-\(poolLength)-\(apiPage)"
    }

    struct CategorySwitchPlan: Equatable {
        var showLoading: Bool
        var preserveLoadedPages: Bool
    }

    static func categorySwitchPlan(hasCachedSnapshot: Bool) -> CategorySwitchPlan {
        CategorySwitchPlan(showLoading: !hasCachedSnapshot, preserveLoadedPages: hasCachedSnapshot)
    }

    static func pullRefreshPlan(hasContent: Bool) -> CategorySwitchPlan {
        CategorySwitchPlan(showLoading: !hasContent, preserveLoadedPages: hasContent)
    }

    static func clampedDisplayCount(current: Int, poolLength: Int) -> Int {
        min(max(current, 0), max(poolLength, 0))
    }

    static func replaceFirstPage(pool _: [VodItem], incoming: [VodItem]) -> [VodItem] {
        mergeIntoPool(pool: [], incoming: incoming, isFirstBatch: true)
    }

    static func refreshFirstPage(pool: [VodItem], incoming: [VodItem]) -> [VodItem] {
        let head = replaceFirstPage(pool: [], incoming: incoming)
        let headKeys = Set(head.map { mergeKey(for: $0) })
        return head + pool.filter { !headKeys.contains(mergeKey(for: $0)) }
    }

    static func mergeIntoPool(pool: [VodItem], incoming: [VodItem], isFirstBatch: Bool) -> [VodItem] {
        var orderedKeys: [String] = []
        var map: [String: VodItem] = [:]

        func consume(_ items: [VodItem], overwrite: Bool) {
            for item in items {
                let key = mergeKey(for: item)
                if map[key] == nil {
                    orderedKeys.append(key)
                    map[key] = item
                } else if overwrite {
                    map[key] = item
                }
            }
        }

        if isFirstBatch {
            consume(pool, overwrite: true)
            consume(incoming, overwrite: true)
            return orderedKeys.prefix(fetchSize).compactMap { map[$0] }
        }

        consume(pool, overwrite: false)
        consume(incoming, overwrite: false)
        let existing = Set(pool.map { mergeKey(for: $0) })
        let newcomers = orderedKeys.filter { !existing.contains($0) }
        return pool + newcomers.prefix(fetchSize).compactMap { map[$0] }
    }
}

struct HomeFeedSnapshot: Equatable {
    var pool: [VodItem]
    var displayCount: Int
    var apiPage: Int
    var pageCount: Int
}

struct HomeFeedCache {
    private var storage: [String: HomeFeedSnapshot] = [:]

    static func key(for typeId: Int?) -> String {
        typeId.map(String.init) ?? "all"
    }

    mutating func save(_ snapshot: HomeFeedSnapshot, typeId: Int?) {
        storage[Self.key(for: typeId)] = snapshot
    }

    func snapshot(for typeId: Int?) -> HomeFeedSnapshot? {
        storage[Self.key(for: typeId)]
    }
}
