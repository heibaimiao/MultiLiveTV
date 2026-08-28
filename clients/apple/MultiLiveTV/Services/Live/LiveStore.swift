import Foundation

final class LiveStore {
    private let sources: [LiveSource]

    init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "lives", withExtension: "json") else {
            throw LiveError.missingLives
        }
        let data = try Data(contentsOf: url)
        sources = try JSONDecoder().decode([LiveSource].self, from: data)
    }

    init(sources: [LiveSource]) {
        self.sources = sources
    }

    func all() -> [LiveSource] { sources }

    func enabled() -> [LiveSource] {
        sources.filter { $0.flag == 0 && !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
