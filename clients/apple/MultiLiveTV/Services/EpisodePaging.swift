import Foundation

enum EpisodePaging {
    static let pageSize = 40

    struct Page: Equatable {
        let start: Int
        let endInclusive: Int
        let label: String
    }

    static func pages(count: Int, pageSize: Int = pageSize) -> [Page] {
        guard count > 0 else { return [] }
        let size = max(pageSize, 1)
        var result: [Page] = []
        var start = 0
        while start < count {
            let end = min(start + size - 1, count - 1)
            result.append(Page(start: start, endInclusive: end, label: "\(start + 1)-\(end + 1)"))
            start += size
        }
        return result
    }

    static func slice<T>(_ items: [T], page: Page) -> [T] {
        guard !items.isEmpty else { return [] }
        let start = min(max(page.start, 0), items.count - 1)
        let end = min(max(page.endInclusive + 1, start + 1), items.count)
        return Array(items[start..<end])
    }
}

enum AsyncTimeout {
    static func run<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                try? await operation()
            }
            group.addTask {
                let nanos = UInt64(max(seconds, 0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

enum UnifiedFetchPlan {
    static let maxInFlight = 6
    static let perCallTimeout: TimeInterval = 5
    static let firstPaintTimeout: TimeInterval = 4
}
