package com.heibaimiao.multilivetv.model

import com.heibaimiao.multilivetv.display.VodDisplayFormatter
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SourceConnection(
    val endpoint: String,
    @SerialName("search_endpoint") val searchEndpoint: String? = null,
    @SerialName("detail_endpoint") val detailEndpoint: String? = null,
    @SerialName("play_endpoint") val playEndpoint: String? = null,
    @SerialName("jx_url") val jxUrl: String? = null,
)

@Serializable
data class SourceCapabilities(
    val search: Boolean = true,
    val category: Boolean = true,
    val detail: Boolean = true,
    val play: Boolean = true,
    val pagination: Boolean = true,
    val live: Boolean = false,
) {
    companion object {
        val cmsDefaults = SourceCapabilities()
    }
}

@Serializable
data class SourceAdapterConfig(
    val type: String = "cms_json",
    val parser: String = "default_cms_parser",
) {
    companion object {
        val cmsJSON = SourceAdapterConfig()
    }
}

@Serializable
data class SourcePriority(
    @SerialName("metadata_priority") val metadataPriority: Int = 100,
    @SerialName("play_priority") val playPriority: Int = 100,
)

@Serializable
data class Source(
    @SerialName("source_id") val sourceId: String,
    val numericId: Int,
    val name: String,
    val type: String = "cms",
    @SerialName("protocol") val protocolName: String = "json",
    val enabled: Boolean = true,
    val inApp: Boolean? = true,
    @SerialName("vip_only") val vipOnly: Boolean? = false,
    val connection: SourceConnection,
    val capabilities: SourceCapabilities = SourceCapabilities.cmsDefaults,
    val adapter: SourceAdapterConfig = SourceAdapterConfig.cmsJSON,
    val priority: SourcePriority = SourcePriority(),
) {
    val id: Int get() = numericId
    val url: String get() = connection.endpoint
    val jxUrl: String? get() = connection.jxUrl

    companion object {
        fun legacy(
            id: Int,
            name: String,
            url: String,
            flag: Int = 0,
            jxUrl: String? = null,
            vipOnly: Boolean? = false,
            capabilities: SourceCapabilities = SourceCapabilities.cmsDefaults,
            metadataPriority: Int = 100,
            playPriority: Int = 100,
        ): Source = Source(
            sourceId = "cms-$id",
            numericId = id,
            name = name,
            enabled = flag == 0,
            vipOnly = vipOnly,
            connection = SourceConnection(endpoint = url, jxUrl = jxUrl),
            capabilities = capabilities,
            priority = SourcePriority(metadataPriority, playPriority),
        )
    }
}

@Serializable
data class SourceRegistryDocument(
    val version: Int = 0,
    val sources: List<Source> = emptyList(),
)

@Serializable
data class LegacySource(
    val id: Int,
    val name: String,
    val url: String,
    val flag: Int = 0,
    @SerialName("jx_url") val jxUrl: String? = null,
    @SerialName("vip_only") val vipOnly: Boolean? = false,
) {
    fun toSource(): Source = Source.legacy(
        id = id,
        name = name,
        url = url,
        flag = flag,
        jxUrl = jxUrl,
        vipOnly = vipOnly,
    )
}

@Serializable
data class VodVariant(
    val sourceId: Int,
    val sourceName: String,
    val vodId: String,
)

@Serializable
data class VodItem(
    @SerialName("vod_id") val vodId: String,
    @SerialName("vod_name") val vodName: String,
    @SerialName("vod_pic") val vodPic: String,
    @SerialName("vod_remarks") val vodRemarks: String? = null,
    @SerialName("vod_blurb") val vodBlurb: String? = null,
    @SerialName("vod_content") val vodContent: String? = null,
    @SerialName("type_name") val typeName: String? = null,
    @SerialName("vod_class") val vodClass: String? = null,
    @SerialName("vod_year") val vodYear: String? = null,
    val variants: List<VodVariant>? = null,
    val primarySourceId: Int? = null,
    @SerialName("vod_time") val vodTime: Int = 0,
) {
    val id: String
        get() = when {
            primarySourceId != null -> "$primarySourceId:$vodId"
            !variants.isNullOrEmpty() -> "${variants.first().sourceId}:$vodId"
            else -> "x:$vodId:$vodName"
        }

    val resolvedSourceId: Int
        get() = primarySourceId ?: variants?.firstOrNull()?.sourceId ?: 33

    val displayBlurb: String?
        get() {
            val text = if (!vodContent.isNullOrEmpty()) vodContent else vodBlurb.orEmpty()
            return VodDisplayFormatter.plainText(text)
        }

    val displayRemarks: String?
        get() = VodDisplayFormatter.formatRemarks(vodRemarks)

    val displayGenreLine: String?
        get() = VodDisplayFormatter.genreLine(typeName, vodYear)
}

@Serializable
data class CategoryDef(
    val typeId: Int,
    val label: String,
)

@Serializable
data class Episode(
    val name: String,
    val url: String,
) {
    val id: String get() = url
}

@Serializable
data class PlaySource(
    val name: String,
    val key: String,
    val episodes: List<Episode>,
    val sourceId: Int? = null,
    val weight: Int = 0,
    val mode: String = "direct",
    val playFrom: String? = null,
    val providerId: String? = null,
    val ticket: String? = null,
    val requiresAuth: Boolean = false,
) {
    val id: String get() = key
}

@Serializable
data class ListResponse(
    val source: SourceRef? = null,
    val typeId: Int? = null,
    val page: Int,
    val pagecount: Int,
    val total: Int,
    val list: List<VodItem>,
) {
    @Serializable
    data class SourceRef(val id: Int, val name: String)
}

@Serializable
data class TypesResponse(
    val source: ListResponse.SourceRef,
    val categories: List<CategoryDef>,
)

@Serializable
data class DetailResponse(
    val vod: VodItem,
    val playSources: List<PlaySource>,
    val variants: List<VodVariant>,
    val merged: Boolean,
)

@Serializable
data class ParseResponse(
    val url: String,
    val parsed: Boolean,
    val mode: String? = "direct",
    val expiresAt: Long? = null,
)

enum class VodError(val message: String) {
    MISSING_SOURCES("未找到 source-registry.json"),
    SOURCE_NOT_FOUND("资源站不存在"),
    VOD_NOT_FOUND("未找到影片"),
}
