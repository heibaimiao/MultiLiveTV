import Foundation

struct UnifiedCategoryNode: Codable {
    let slug: String
    let label: String
    let sources: [String: Int]
    let children: [UnifiedCategoryNode]?
}

struct UnifiedCatalogFile: Codable {
    let version: Int
    let generatedAt: String?
    let aliases: [String: String]?
    let defaultSlug: String
    let tree: [UnifiedCategoryNode]

    enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case aliases
        case defaultSlug
        case tree
    }
}

struct SlugCategory: Codable, Identifiable, Hashable {
    var id: String { slug }
    let slug: String
    let label: String
}

enum UnifiedCategories {
    static let bundled: UnifiedCatalogFile = {
        if let url = Bundle.main.url(forResource: "unified-categories", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let catalog = try? JSONDecoder().decode(UnifiedCatalogFile.self, from: data) {
            return catalog
        }
        return UnifiedCatalogFile(
            version: 1,
            generatedAt: nil,
            aliases: nil,
            defaultSlug: "movie",
            tree: [
                UnifiedCategoryNode(slug: "movie", label: "电影", sources: [:], children: []),
                UnifiedCategoryNode(slug: "tv", label: "剧集", sources: [:], children: []),
                UnifiedCategoryNode(slug: "variety", label: "综艺", sources: [:], children: []),
                UnifiedCategoryNode(slug: "anime", label: "动漫", sources: [:], children: []),
                UnifiedCategoryNode(slug: "short", label: "短剧", sources: [:], children: []),
            ]
        )
    }()

    static var defaultSlug: String { bundled.defaultSlug.isEmpty ? "movie" : bundled.defaultSlug }

    static func find(_ slug: String?) -> UnifiedCategoryNode? {
        guard let slug, !slug.isEmpty else { return nil }
        for node in bundled.tree {
            if node.slug == slug { return node }
            if let child = node.children?.first(where: { $0.slug == slug }) {
                return child
            }
        }
        return nil
    }

    static func parentSlug(of slug: String?) -> String? {
        guard let slug else { return nil }
        for node in bundled.tree {
            if node.slug == slug { return node.slug }
            if node.children?.contains(where: { $0.slug == slug }) == true {
                return node.slug
            }
        }
        return nil
    }

    static func label(for slug: String?) -> String {
        guard let slug else { return "全部" }
        return find(slug)?.label ?? slug
    }

    static func mappings(for slug: String) -> [(sourceId: Int, typeId: Int)] {
        guard let node = find(slug) else { return [] }
        return node.sources.compactMap { key, typeId in
            guard let sourceId = Int(key) else { return nil }
            return (sourceId, typeId)
        }
    }

    static func tree() -> CategoryTree {
        CategoryTreeBuilder.build(from: bundled)
    }
}
