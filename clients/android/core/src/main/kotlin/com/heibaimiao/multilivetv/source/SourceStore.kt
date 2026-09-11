package com.heibaimiao.multilivetv.source

import com.heibaimiao.multilivetv.model.LegacySource
import com.heibaimiao.multilivetv.model.Source
import com.heibaimiao.multilivetv.model.SourceCapabilities
import com.heibaimiao.multilivetv.model.SourceRegistryDocument
import com.heibaimiao.multilivetv.model.VodError
import com.heibaimiao.multilivetv.net.VodClientException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

enum class SourceCapability {
    SEARCH, CATEGORY, DETAIL, PLAY, PAGINATION, LIVE
}

class SourceStore(private val sources: List<Source>) {
    private val byNumericId = sources.associateBy { it.numericId }
    private val bySourceIdKey = sources.associateBy { it.sourceId }

    constructor() : this(loadRegistry().sources)

    fun all(): List<Source> = sources

    fun configured(id: Int): Source? = byNumericId[id]

    fun configured(sourceId: String): Source? = bySourceIdKey[sourceId]

    fun enabled(): List<Source> = sources.filter { it.enabled && it.vipOnly != true }

    fun collectable(capability: SourceCapability): List<Source> = enabled().filter { source ->
        when (capability) {
            SourceCapability.SEARCH -> source.capabilities.search
            SourceCapability.CATEGORY -> source.capabilities.category
            SourceCapability.DETAIL -> source.capabilities.detail
            SourceCapability.PLAY -> source.capabilities.play
            SourceCapability.PAGINATION -> source.capabilities.pagination
            SourceCapability.LIVE -> source.capabilities.live
        }
    }

    fun byID(id: Int): Source? {
        val source = byNumericId[id] ?: return null
        if (!source.enabled || source.vipOnly == true) return null
        return source
    }

    fun bySourceID(sourceId: String): Source? {
        val source = bySourceIdKey[sourceId] ?: return null
        if (!source.enabled || source.vipOnly == true) return null
        return source
    }

    fun default(): Source? = enabled().firstOrNull()

    fun metadataPriority(numericId: Int): Int =
        configured(numericId)?.priority?.metadataPriority ?: 100

    fun playPriority(numericId: Int): Int =
        configured(numericId)?.priority?.playPriority ?: 100

    companion object {
        private val json = Json { ignoreUnknownKeys = true; isLenient = true }

        fun loadRegistry(
            registryText: String? = resourceOrNull("source-registry.json"),
            legacyText: String? = resourceOrNull("sources.json"),
        ): SourceRegistryDocument {
            if (registryText != null) {
                return json.decodeFromString(SourceRegistryDocument.serializer(), registryText)
            }
            if (legacyText != null) {
                val legacy = json.decodeFromString(ListSerializer(LegacySource.serializer()), legacyText)
                return SourceRegistryDocument(version = 0, sources = legacy.map { it.toSource() })
            }
            throw VodClientException(VodError.MISSING_SOURCES.message)
        }

        private fun resourceOrNull(name: String): String? {
            val stream = SourceStore::class.java.classLoader?.getResourceAsStream(name) ?: return null
            return stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        }
    }
}

fun Source.supports(capability: SourceCapability): Boolean = when (capability) {
    SourceCapability.SEARCH -> capabilities.search
    SourceCapability.CATEGORY -> capabilities.category
    SourceCapability.DETAIL -> capabilities.detail
    SourceCapability.PLAY -> capabilities.play
    SourceCapability.PAGINATION -> capabilities.pagination
    SourceCapability.LIVE -> capabilities.live
}

fun SourceCapabilities.has(capability: SourceCapability): Boolean = when (capability) {
    SourceCapability.SEARCH -> search
    SourceCapability.CATEGORY -> category
    SourceCapability.DETAIL -> detail
    SourceCapability.PLAY -> play
    SourceCapability.PAGINATION -> pagination
    SourceCapability.LIVE -> live
}
