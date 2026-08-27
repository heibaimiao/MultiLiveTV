import Foundation

enum HomeFeed {
    static let fetchSize = 50
    static let initialDisplay = 30
    static let scrollLoadSize = 20

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

    static func mergeIntoPool(pool: [VodItem], incoming: [VodItem], isFirstBatch: Bool) -> [VodItem] {
        var map: [String: VodItem] = [:]
        for item in pool { map[mergeKey(for: item)] = item }
        for item in incoming { map[mergeKey(for: item)] = item }
        let merged = Array(map.values)
        if isFirstBatch {
            return Array(merged.prefix(fetchSize))
        }
        let existing = Set(pool.map { mergeKey(for: $0) })
        let newcomers = merged.filter { !existing.contains(mergeKey(for: $0)) }
        return pool + newcomers.prefix(fetchSize)
    }
}
