package com.heibaimiao.multilivetv.category

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class UnifiedCategoryNode(
    val slug: String,
    val label: String,
    val sources: Map<String, Int> = emptyMap(),
    val children: List<UnifiedCategoryNode>? = emptyList(),
)

@Serializable
data class UnifiedCatalogFile(
    val version: Int,
    @SerialName("generated_at") val generatedAt: String? = null,
    val aliases: Map<String, String>? = null,
    val defaultSlug: String = "movie",
    val tree: List<UnifiedCategoryNode> = emptyList(),
)

@Serializable
data class SlugCategory(
    val slug: String,
    val label: String,
)

object UnifiedCategories {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    val bundled: UnifiedCatalogFile by lazy { load() }

    val defaultSlug: String
        get() = bundled.defaultSlug.ifEmpty { "movie" }

    fun find(slug: String?): UnifiedCategoryNode? {
        if (slug.isNullOrEmpty()) return null
        for (node in bundled.tree) {
            if (node.slug == slug) return node
            node.children?.firstOrNull { it.slug == slug }?.let { return it }
        }
        return null
    }

    fun mappings(slug: String): List<Pair<Int, Int>> {
        val node = find(slug) ?: return emptyList()
        return node.sources.mapNotNull { (key, typeId) ->
            key.toIntOrNull()?.let { it to typeId }
        }
    }

    fun listTypeIds(slug: String, sourceId: Int): List<Int> {
        val node = find(slug) ?: return emptyList()
        val key = sourceId.toString()
        val childIds = (node.children ?: emptyList())
            .mapNotNull { it.sources[key] }
            .distinct()
        if (childIds.isNotEmpty()) return childIds
        return listOfNotNull(node.sources[key])
    }

    fun tree(): CategoryTree = CategoryTreeBuilder.build(bundled)

    private fun load(): UnifiedCatalogFile {
        val text = UnifiedCategories::class.java.classLoader
            ?.getResourceAsStream("unified-categories.json")
            ?.bufferedReader(Charsets.UTF_8)
            ?.use { it.readText() }
        if (text != null) return json.decodeFromString(UnifiedCatalogFile.serializer(), text)
        return UnifiedCatalogFile(
            version = 1,
            defaultSlug = "movie",
            tree = listOf(
                UnifiedCategoryNode("movie", "电影"),
                UnifiedCategoryNode("tv", "剧集"),
                UnifiedCategoryNode("variety", "综艺"),
                UnifiedCategoryNode("anime", "动漫"),
                UnifiedCategoryNode("short", "短剧"),
            ),
        )
    }
}

data class CategoryTree(
    val all: List<SlugCategory>,
    val primary: List<SlugCategory>,
    val childrenByParent: Map<String, List<SlugCategory>>,
) {
    companion object {
        val empty = CategoryTree(emptyList(), emptyList(), emptyMap())
    }
}

object CategoryTreeBuilder {
    fun build(catalog: UnifiedCatalogFile): CategoryTree {
        val all = mutableListOf<SlugCategory>()
        val primary = mutableListOf<SlugCategory>()
        val childrenByParent = mutableMapOf<String, List<SlugCategory>>()
        for (node in catalog.tree) {
            val parent = SlugCategory(node.slug, node.label)
            primary += parent
            all += parent
            val children = (node.children ?: emptyList()).map { SlugCategory(it.slug, it.label) }
            childrenByParent[node.slug] = children
            all += children
        }
        return CategoryTree(all, primary, childrenByParent)
    }

    fun parentSlug(tree: CategoryTree, slug: String?): String? {
        if (slug == null) return null
        if (tree.primary.any { it.slug == slug }) return slug
        for ((parent, children) in tree.childrenByParent) {
            if (children.any { it.slug == slug }) return parent
        }
        return null
    }

    fun defaultSlug(tree: CategoryTree): String? =
        tree.primary.firstOrNull { it.slug == "movie" }?.slug
            ?: tree.primary.firstOrNull { it.label == "电影" }?.slug
            ?: tree.primary.firstOrNull()?.slug
}
