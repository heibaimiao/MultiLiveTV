import Foundation

enum TopShelfStore {
    static let appGroupId = "group.com.heibaimiao.multilivetv"
    static let fileName = "topshelf.json"
    static let itemLimit = 6

    static func sanitized(_ snapshots: [TopShelfSnapshot], limit: Int = itemLimit) -> [TopShelfSnapshot] {
        var result: [TopShelfSnapshot] = []
        result.reserveCapacity(min(limit, snapshots.count))
        for snapshot in snapshots {
            if result.count >= limit { break }
            guard RemoteMediaURL.parse(snapshot.vodPic) != nil else { continue }
            result.append(snapshot)
        }
        return result
    }

    @discardableResult
    static func save(_ snapshots: [TopShelfSnapshot], directory: URL? = nil) -> Bool {
        let items = sanitized(snapshots)
        guard let directory = directory ?? containerDirectory() else { return false }
        let url = directory.appendingPathComponent(fileName)
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func load(directory: URL? = nil) -> [TopShelfSnapshot] {
        guard let directory = directory ?? containerDirectory() else { return [] }
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([TopShelfSnapshot].self, from: data)) ?? []
    }

    static func containerDirectory() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }
}
