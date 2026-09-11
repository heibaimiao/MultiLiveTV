package com.heibaimiao.multilivetv.category

import com.heibaimiao.multilivetv.maccms.VodTypeRaw
import com.heibaimiao.multilivetv.model.CategoryDef
import com.heibaimiao.multilivetv.model.VodItem

object MacCMSCategoryService {
    private val typeAliases = mapOf(
        "日本剧" to "日剧", "韩国剧" to "韩剧", "泰国剧" to "泰剧", "台湾剧" to "台剧",
        "香港剧" to "港剧", "大陆剧" to "国产剧", "记录片" to "纪录片", "日本动漫" to "日韩动漫",
        "连续剧" to "剧集", "电影片" to "电影", "综艺片" to "综艺", "动漫片" to "动漫",
    )
    private val parentNames = setOf("电影", "剧集", "综艺", "动漫")

    fun normalizeTypeName(typeName: String): String {
        var cleaned = typeName.replace(Regex("""\[关]"""), "").trim()
        if (cleaned.endsWith("x", ignoreCase = true)) {
            cleaned = cleaned.dropLast(1).trim()
        }
        return typeAliases[cleaned] ?: cleaned
    }

    fun isHiddenCategoryLabel(text: String): Boolean = "伦理" in text || "倫理" in text

    fun isTypeVisible(typeName: String): Boolean {
        if ("[关]" in typeName) return false
        if (typeName.endsWith("x", ignoreCase = true)) return false
        if (isHiddenCategoryLabel(typeName)) return false
        return true
    }

    fun isItemVisible(item: VodItem): Boolean {
        if (!item.typeName.isNullOrEmpty() && isHiddenCategoryLabel(item.typeName)) return false
        if (!item.vodClass.isNullOrEmpty() && isHiddenCategoryLabel(item.vodClass)) return false
        return true
    }

    fun filterVisibleTypes(types: List<VodTypeRaw>): List<VodTypeRaw> =
        types.filter { isTypeVisible(it.typeName) }

    fun buildCategories(types: List<VodTypeRaw>): List<CategoryDef> =
        filterVisibleTypes(types).map { CategoryDef(it.typeId, normalizeTypeName(it.typeName)) }

    fun getChildTypeIds(types: List<VodTypeRaw>, parentId: Int): List<Int> {
        val parent = types.firstOrNull { it.typeId == parentId } ?: return emptyList()
        val parentName = normalizeTypeName(parent.typeName)
        if (parentName !in parentNames) return emptyList()
        val candidates = filterVisibleTypes(types).filter {
            it.typeId != parentId && normalizeTypeName(it.typeName) !in parentNames
        }
        val matcher: (String) -> Boolean = when (parentName) {
            "电影" -> { name -> (name.endsWith("片") || name == "纪录片") && "动漫" !in name && "动画" !in name }
            "剧集" -> { name -> name.endsWith("剧") && name != "短剧" }
            "综艺" -> { name -> "综艺" in name }
            "动漫" -> { name -> "动漫" in name || "动画" in name }
            else -> return emptyList()
        }
        return candidates.filter { matcher(normalizeTypeName(it.typeName)) }.map { it.typeId }
    }
}

object CategoryMatch {
    fun excludingHidden(items: List<VodItem>): List<VodItem> =
        items.filter(MacCMSCategoryService::isItemVisible)

    fun filter(items: List<VodItem>, selectedSlug: String?, tree: CategoryTree): List<VodItem> {
        val visible = excludingHidden(items)
        if (selectedSlug == null) return visible
        val allowed = allowedLabels(selectedSlug, tree)
        if (allowed.isEmpty()) return visible
        return visible.filter { matches(it, allowed) }
    }

    fun allowedLabels(selectedSlug: String, tree: CategoryTree): Set<String> {
        val selected = tree.all.firstOrNull { it.slug == selectedSlug } ?: return emptySet()
        val labels = mutableSetOf(normalized(selected.label))
        tree.childrenByParent[selectedSlug]?.forEach { labels += normalized(it.label) }
        return labels
    }

    fun matches(item: VodItem, allowed: Set<String>): Boolean {
        val typeName = item.typeName?.let(::normalized).orEmpty()
        if (typeName.isNotEmpty() && typeName in allowed) return true
        val classText = item.vodClass.orEmpty()
        if (typeName.isEmpty() && classText.isEmpty()) return true
        if (classText.isEmpty()) return false
        return classTokens(classText).any { token ->
            allowed.any { label -> tokenMatches(label, token) }
        }
    }

    private fun normalized(name: String): String = MacCMSCategoryService.normalizeTypeName(name)

    private fun classTokens(vodClass: String): List<String> =
        vodClass.split(Regex("""[,/|、， ]""")).map(::normalized).filter { it.isNotEmpty() }

    private fun tokenMatches(label: String, token: String): Boolean {
        if (token == label) return true
        val stem = classStem(label)
        return token == stem || token.startsWith(stem) || (stem.startsWith(token) && token.length >= 2)
    }

    private fun classStem(label: String): String = when {
        label.endsWith("片") && label.length > 1 -> label.dropLast(1)
        label.endsWith("剧") && label.length > 1 && label != "剧集" -> label.dropLast(1)
        else -> label
    }
}
