import Foundation

final class DownloadStore {
    let rootURL: URL

    private var indexURL: URL {
        rootURL.appendingPathComponent("index.json")
    }

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    static func defaultRoot() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("downloads", isDirectory: true)
    }

    func filesDirectory(for id: String) -> URL {
        rootURL
            .appendingPathComponent("files", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    func load() -> [DownloadRecord] {
        guard FileManager.default.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              let records = try? JSONDecoder().decode([DownloadRecord].self, from: data) else {
            return []
        }
        return records
    }

    func save(_ records: [DownloadRecord]) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(records)
        try data.write(to: indexURL, options: .atomic)
        excludeFromBackup(rootURL)
    }

    func upsert(_ record: DownloadRecord) throws {
        var all = load()
        if let index = all.firstIndex(where: { $0.id == record.id }) {
            all[index] = record
        } else {
            all.append(record)
        }
        try save(all)
    }

    func delete(id: String) throws {
        var all = load()
        all.removeAll { $0.id == id }
        try save(all)
        let directory = filesDirectory(for: id)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func reconcileEvicted(_ records: [DownloadRecord]) -> [DownloadRecord] {
        records.map { record in
            guard record.status == .completed else { return record }
            let exists = record.localPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
            guard !exists else { return record }
            var copy = record
            copy.status = .evicted
            copy.errorMessage = "已被系统清理"
            return copy
        }
    }

    func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
    }
}
