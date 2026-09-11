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

    static func normalizeYear(_ year: String?) -> String {
        guard let year else { return "" }
        let trimmed = year.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.range(of: #"\d{4}"#, options: .regularExpression) else {
            return ""
        }
        let digits = String(trimmed[match])
        guard let value = Int(digits), isDisplayableReleaseYear(value) else {
            return ""
        }
        return digits
    }

    /// Years used for ranking. Future placeholders (e.g. 2030) map to the current
    /// calendar year so recently-added titles still surface with this year's films.
    static func sortYearValue(_ year: String?, vodTime: Int = 0, now: Date = Date()) -> Int {
        let current = Calendar(identifier: .gregorian).component(.year, from: now)
        if let digits = rawYearDigits(year), let value = Int(digits) {
            if value >= 1900 && value <= current + 1 {
                return value
            }
            if value > current + 1 {
                return current
            }
        }
        return yearFromVodTime(vodTime, fallback: 0)
    }

    static func yearValue(_ year: String?) -> Int {
        Int(normalizeYear(year)) ?? 0
    }

    /// MacCMS often fills placeholder years (e.g. 2030). Hide those on the card.
    static func isDisplayableReleaseYear(_ year: Int, now: Date = Date()) -> Bool {
        let current = Calendar(identifier: .gregorian).component(.year, from: now)
        return year >= 1900 && year <= current + 1
    }

    private static func rawYearDigits(_ year: String?) -> String? {
        guard let year else { return nil }
        let trimmed = year.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.range(of: #"\d{4}"#, options: .regularExpression) else {
            return nil
        }
        return String(trimmed[match])
    }

    private static func yearFromVodTime(_ vodTime: Int, fallback: Int) -> Int {
        guard vodTime > 0 else { return fallback }
        let date = Date(timeIntervalSince1970: TimeInterval(vodTime))
        return Calendar(identifier: .gregorian).component(.year, from: date)
    }

    /// Release year first (placeholders treated as this year), then update time.
    static func sortByUpdatedDesc(_ items: [VodItem]) -> [VodItem] {
        items.enumerated()
            .sorted { lhs, rhs in
                let ly = sortYearValue(lhs.element.vodYear, vodTime: lhs.element.vodTime)
                let ry = sortYearValue(rhs.element.vodYear, vodTime: rhs.element.vodTime)
                if ly != ry {
                    return ly > ry
                }
                if lhs.element.vodTime != rhs.element.vodTime {
                    return lhs.element.vodTime > rhs.element.vodTime
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func mergeKey(for item: VodItem) -> String {
        mergeKey(title: item.vodName, year: item.vodYear)
    }

    static func mergeKey(title: String, year: String?) -> String {
        let normalized = normalizeTitle(title)
        let year = normalizeYear(year)
        if year.isEmpty { return normalized }
        return "\(normalized)|\(year)"
    }

    /// Prefer an existing title|year key when the new row has no year (or vice versa).
    static func resolvePoolMergeKey(for item: VodItem, existingKeys: [String]) -> String {
        let title = normalizeTitle(item.vodName)
        guard !title.isEmpty else { return mergeKey(for: item) }
        let year = normalizeYear(item.vodYear)
        let bare = title
        let yeared = year.isEmpty ? nil : "\(title)|\(year)"
        let titleKeys = existingKeys.filter { $0 == bare || $0.hasPrefix("\(title)|") }

        if let yeared {
            if titleKeys.contains(yeared) { return yeared }
            if titleKeys.contains(bare) { return yeared }
            return yeared
        }

        let yearedKeys = titleKeys.filter { $0.contains("|") }
        if yearedKeys.count == 1 { return yearedKeys[0] }
        if titleKeys.contains(bare) { return bare }
        return bare
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
        Array(sortedByUpdatedDesc(pool).prefix(hotSize))
    }

    static func recentItems(_ pool: [VodItem]) -> [VodItem] {
        Array(sortedByUpdatedDesc(pool).dropFirst(hotSize).prefix(recentSize))
    }

    static func allItems(_ pool: [VodItem]) -> [VodItem] {
        Array(sortedByUpdatedDesc(pool).dropFirst(hotSize + recentSize))
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

    private static func sortedByUpdatedDesc(_ pool: [VodItem]) -> [VodItem] {
        sortByUpdatedDesc(pool)
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
                let key = resolvePoolMergeKey(for: item, existingKeys: orderedKeys)
                let bare = normalizeTitle(item.vodName)
                if key != bare, map[bare] != nil {
                    if map[key] == nil {
                        map[key] = map[bare]
                        if !orderedKeys.contains(key) {
                            orderedKeys.append(key)
                        }
                    }
                    map[bare] = nil
                    orderedKeys.removeAll { $0 == bare }
                }
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
            let merged = orderedKeys.compactMap { map[$0] }
            return Array(sortByUpdatedDesc(merged).prefix(fetchSize))
        }

        consume(pool, overwrite: false)
        consume(incoming, overwrite: false)
        var seen = Set<String>()
        var combined: [VodItem] = []
        for item in pool {
            let key = resolvePoolMergeKey(for: item, existingKeys: orderedKeys)
            guard seen.insert(key).inserted else { continue }
            combined.append(map[key] ?? item)
        }
        for key in orderedKeys where !seen.contains(key) {
            guard let item = map[key] else { continue }
            guard seen.insert(key).inserted else { continue }
            combined.append(item)
            if combined.count >= pool.count + fetchSize { break }
        }
        return sortByUpdatedDesc(combined)
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

    static func key(for slug: String?) -> String {
        slug ?? "all"
    }

    mutating func save(_ snapshot: HomeFeedSnapshot, slug: String?) {
        storage[Self.key(for: slug)] = snapshot
    }

    func snapshot(for slug: String?) -> HomeFeedSnapshot? {
        storage[Self.key(for: slug)]
    }
}
