import Foundation

struct CategoryTree {
    let all: [CategoryDef]
    let primary: [CategoryDef]
    let childrenByParent: [Int: [CategoryDef]]

    static let empty = CategoryTree(all: [], primary: [], childrenByParent: [:])
}

enum CategoryTreeBuilder {
    private static let parentNames: Set<String> = ["电影", "剧集", "综艺", "动漫"]

    static func build(from all: [CategoryDef]) -> CategoryTree {
        let all = all.filter { MacCMSCategoryService.isTypeVisible($0.label) }
        let parents = all.filter { parentNames.contains($0.label) }

        var childrenByParent: [Int: [CategoryDef]] = [:]
        for parent in parents {
            let childIds = childTypeIds(all: all, parentId: parent.typeId)
            childrenByParent[parent.typeId] = childIds.compactMap { id in
                all.first { $0.typeId == id }
            }
        }

        return CategoryTree(all: all, primary: parents, childrenByParent: childrenByParent)
    }

    static func parentTypeId(tree: CategoryTree, typeId: Int?) -> Int? {
        guard let typeId else { return nil }

        if let children = tree.childrenByParent[typeId], !children.isEmpty,
           tree.primary.contains(where: { $0.typeId == typeId }) {
            return typeId
        }

        for (parentId, children) in tree.childrenByParent {
            if children.contains(where: { $0.typeId == typeId }) {
                return parentId
            }
        }

        if tree.primary.contains(where: { $0.typeId == typeId }) {
            return typeId
        }

        return nil
    }

    static func label(tree: CategoryTree, typeId: Int?) -> String {
        guard let typeId else { return "电影" }
        return tree.all.first { $0.typeId == typeId }?.label ?? String(typeId)
    }

    static func defaultTypeId(in tree: CategoryTree) -> Int? {
        tree.primary.first { $0.label == "电影" }?.typeId ?? tree.primary.first?.typeId
    }

    private static func childTypeIds(all: [CategoryDef], parentId: Int) -> [Int] {
        guard let parent = all.first(where: { $0.typeId == parentId }),
              parentNames.contains(parent.label) else { return [] }

        let candidates = all.filter { $0.typeId != parentId && !parentNames.contains($0.label) }

        let matcher: (String) -> Bool
        switch parent.label {
        case "电影":
            matcher = { name in
                (name.hasSuffix("片") || name == "纪录片") && !name.contains("动漫") && !name.contains("动画")
            }
        case "剧集":
            matcher = { name in name.hasSuffix("剧") && name != "短剧" }
        case "综艺":
            matcher = { name in name.contains("综艺") }
        case "动漫":
            matcher = { name in name.contains("动漫") || name.contains("动画") }
        default:
            return []
        }

        return candidates.filter { matcher($0.label) }.map(\.typeId)
    }
}
