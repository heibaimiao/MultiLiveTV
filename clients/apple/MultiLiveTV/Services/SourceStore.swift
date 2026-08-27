import Foundation

final class SourceStore {
    private let sources: [Source]

    init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "sources", withExtension: "json") else {
            throw VodError.missingSources
        }
        let data = try Data(contentsOf: url)
        sources = try JSONDecoder().decode([Source].self, from: data)
    }

    init(sources: [Source]) {
        self.sources = sources
    }

    func all() -> [Source] { sources }

    func enabled() -> [Source] {
        sources.filter { $0.flag == 0 && ($0.vipOnly != true) }
    }

    func byID(_ id: Int) -> Source? {
        enabled().first { $0.id == id }
    }

    func `default`() -> Source? {
        enabled().first
    }
}

enum VodError: LocalizedError {
    case missingSources
    case sourceNotFound
    case vodNotFound

    var errorDescription: String? {
        switch self {
        case .missingSources: return "未找到 sources.json"
        case .sourceNotFound: return "资源站不存在"
        case .vodNotFound: return "未找到影片"
        }
    }
}
