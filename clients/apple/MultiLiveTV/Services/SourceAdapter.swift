import Foundation

protocol SourceAdapter {
    func list(source: Source, page: Int, typeId: Int?, hours: Int?) async throws -> SourcePage
    func search(source: Source, keyword: String, page: Int) async throws -> SourcePage
    func detail(source: Source, sourceMovieId: String) async throws -> SourceMovie
    func fetchTypes(source: Source) async throws -> [VodTypeRaw]
}

enum SourceAdapterError: LocalizedError {
    case unsupportedAdapter(String)
    case capabilityDisabled(String)
    case emptyDetail

    var errorDescription: String? {
        switch self {
        case .unsupportedAdapter(let type):
            return "不支持的 Adapter: \(type)"
        case .capabilityDisabled(let name):
            return "源不支持能力: \(name)"
        case .emptyDetail:
            return "详情为空"
        }
    }
}

enum SourceAdapterRegistry {
    static func adapter(for source: Source) throws -> SourceAdapter {
        switch source.adapter.type {
        case "cms_json":
            return CMSJsonAdapter.shared
        default:
            throw SourceAdapterError.unsupportedAdapter(source.adapter.type)
        }
    }
}

/// Capability-gated collector used by list / search / detail fan-out.
enum SourceCollector {
    static func list(
        source: Source,
        page: Int,
        typeId: Int?,
        hours: Int? = nil,
        health: SourceHealthStore = .shared
    ) async throws -> SourcePage {
        guard source.enabled else { throw SourceAdapterError.capabilityDisabled("enabled") }
        guard source.capabilities.category else { throw SourceAdapterError.capabilityDisabled("category") }
        let adapter = try SourceAdapterRegistry.adapter(for: source)
        do {
            let pageResult = try await adapter.list(source: source, page: page, typeId: typeId, hours: hours)
            health.recordSuccess(numericId: source.numericId)
            return pageResult
        } catch {
            health.recordFailure(numericId: source.numericId)
            throw error
        }
    }

    static func search(
        source: Source,
        keyword: String,
        page: Int,
        health: SourceHealthStore = .shared
    ) async throws -> SourcePage {
        guard source.enabled else { throw SourceAdapterError.capabilityDisabled("enabled") }
        guard source.capabilities.search else { throw SourceAdapterError.capabilityDisabled("search") }
        let adapter = try SourceAdapterRegistry.adapter(for: source)
        do {
            let pageResult = try await adapter.search(source: source, keyword: keyword, page: page)
            health.recordSuccess(numericId: source.numericId)
            return pageResult
        } catch {
            health.recordFailure(numericId: source.numericId)
            throw error
        }
    }

    static func detail(
        source: Source,
        sourceMovieId: String,
        health: SourceHealthStore = .shared
    ) async throws -> SourceMovie {
        guard source.enabled else { throw SourceAdapterError.capabilityDisabled("enabled") }
        guard source.capabilities.detail else { throw SourceAdapterError.capabilityDisabled("detail") }
        let adapter = try SourceAdapterRegistry.adapter(for: source)
        do {
            let movie = try await adapter.detail(source: source, sourceMovieId: sourceMovieId)
            health.recordSuccess(numericId: source.numericId)
            return movie
        } catch {
            health.recordFailure(numericId: source.numericId)
            throw error
        }
    }

    static func fetchTypes(source: Source) async throws -> [VodTypeRaw] {
        guard source.enabled else { throw SourceAdapterError.capabilityDisabled("enabled") }
        let adapter = try SourceAdapterRegistry.adapter(for: source)
        return try await adapter.fetchTypes(source: source)
    }
}

struct CMSJsonAdapter: SourceAdapter {
    static let shared = CMSJsonAdapter()

    func list(source: Source, page: Int, typeId: Int?, hours: Int?) async throws -> SourcePage {
        let effectivePage = source.capabilities.pagination ? page : 1
        let response = try await MacCMSClient.fetchList(
            source: source,
            page: effectivePage,
            typeId: typeId,
            hours: hours
        )
        return SourcePage(
            page: response.page,
            pageCount: response.pageCount,
            total: response.total,
            list: response.list.map { MacCMSSourceParser.toSourceMovie(source: source, raw: $0) }
        )
    }

    func search(source: Source, keyword: String, page: Int) async throws -> SourcePage {
        let effectivePage = source.capabilities.pagination ? page : 1
        let response = try await MacCMSClient.search(source: source, keyword: keyword, page: effectivePage)
        return SourcePage(
            page: response.page,
            pageCount: response.pageCount,
            total: response.total,
            list: response.list.map { MacCMSSourceParser.toSourceMovie(source: source, raw: $0) }
        )
    }

    func detail(source: Source, sourceMovieId: String) async throws -> SourceMovie {
        let response = try await MacCMSClient.fetchDetail(source: source, ids: sourceMovieId)
        guard let raw = response.list.first else { throw SourceAdapterError.emptyDetail }
        return MacCMSSourceParser.toSourceMovie(source: source, raw: raw)
    }

    func fetchTypes(source: Source) async throws -> [VodTypeRaw] {
        try await MacCMSClient.fetchTypes(source: source)
    }
}
