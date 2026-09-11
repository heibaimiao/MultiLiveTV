import Foundation

struct CategoryTree {
    let all: [SlugCategory]
    let primary: [SlugCategory]
    let childrenByParent: [String: [SlugCategory]]

    static let empty = CategoryTree(all: [], primary: [], childrenByParent: [:])
}

enum CategoryTreeBuilder {
    static func build(from catalog: UnifiedCatalogFile) -> CategoryTree {
        var all: [SlugCategory] = []
        var primary: [SlugCategory] = []
        var childrenByParent: [String: [SlugCategory]] = [:]

        for node in catalog.tree {
            let parent = SlugCategory(slug: node.slug, label: node.label)
            primary.append(parent)
            all.append(parent)
            let children = (node.children ?? []).map { SlugCategory(slug: $0.slug, label: $0.label) }
            childrenByParent[node.slug] = children
            all.append(contentsOf: children)
        }

        return CategoryTree(all: all, primary: primary, childrenByParent: childrenByParent)
    }

    static func parentSlug(tree: CategoryTree, slug: String?) -> String? {
        guard let slug else { return nil }
        if tree.primary.contains(where: { $0.slug == slug }) {
            return slug
        }
        for (parent, children) in tree.childrenByParent {
            if children.contains(where: { $0.slug == slug }) {
                return parent
            }
        }
        return nil
    }

    static func label(tree: CategoryTree, slug: String?) -> String {
        guard let slug else { return "全部" }
        return tree.all.first { $0.slug == slug }?.label ?? slug
    }

    static func defaultSlug(in tree: CategoryTree) -> String? {
        tree.primary.first { $0.slug == "movie" }?.slug
            ?? tree.primary.first { $0.label == "电影" }?.slug
            ?? tree.primary.first?.slug
    }
}
