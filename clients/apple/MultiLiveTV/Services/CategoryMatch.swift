import Foundation

enum CategoryMatch {
    static func excludingHidden(_ items: [VodItem]) -> [VodItem] {
        items.filter(MacCMSCategoryService.isItemVisible)
    }

    static func filter(_ items: [VodItem], selectedTypeId: Int?, tree: CategoryTree) -> [VodItem] {
        let items = excludingHidden(items)
        guard let selectedTypeId else { return items }
        let allowed = allowedLabels(selectedTypeId: selectedTypeId, tree: tree)
        guard !allowed.isEmpty else { return items }
        return items.filter { matches($0, allowed: allowed) }
    }

    static func allowedLabels(selectedTypeId: Int, tree: CategoryTree) -> Set<String> {
        guard let selected = tree.all.first(where: { $0.typeId == selectedTypeId }) else { return [] }
        var labels: Set<String> = [normalized(selected.label)]
        if let children = tree.childrenByParent[selectedTypeId] {
            for child in children {
                labels.insert(normalized(child.label))
            }
        }
        return labels
    }

    static func matches(_ item: VodItem, allowed: Set<String>) -> Bool {
        let typeName = item.typeName.map(normalized) ?? ""
        if !typeName.isEmpty, allowed.contains(typeName) {
            return true
        }

        let classText = item.vodClass ?? ""
        if typeName.isEmpty, classText.isEmpty {
            return true
        }

        if classText.isEmpty {
            return false
        }

        return classTokens(classText).contains { token in
            allowed.contains { label in tokenMatches(label: label, token: token) }
        }
    }

    private static func normalized(_ name: String) -> String {
        MacCMSCategoryService.normalizeTypeName(name)
    }

    private static func classTokens(_ vodClass: String) -> [String] {
        vodClass
            .split(whereSeparator: { ",/|、， ".contains($0) })
            .map { normalized(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func tokenMatches(label: String, token: String) -> Bool {
        if token == label { return true }
        let stem = classStem(label)
        return token == stem || token.hasPrefix(stem) || stem.hasPrefix(token) && token.count >= 2
    }

    private static func classStem(_ label: String) -> String {
        if label.hasSuffix("片"), label.count > 1 {
            return String(label.dropLast())
        }
        if label.hasSuffix("剧"), label.count > 1, label != "剧集" {
            return String(label.dropLast())
        }
        return label
    }
}
