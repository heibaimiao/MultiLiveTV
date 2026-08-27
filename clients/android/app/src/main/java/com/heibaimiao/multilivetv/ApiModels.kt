package com.heibaimiao.multilivetv

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import retrofit2.http.GET
import retrofit2.http.Query

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
    val variants: List<VodVariant>? = null,
    val primarySourceId: Int? = null,
)

@Serializable
data class SearchResponse(
    val keyword: String,
    val merged: Boolean,
    val total: Int,
    val list: List<VodItem>,
)

@Serializable
data class Episode(val name: String, val url: String)

@Serializable
data class PlaySource(
    val name: String,
    val key: String,
    val episodes: List<Episode>,
    val sourceId: Int? = null,
)

@Serializable
data class DetailResponse(
    val vod: VodItem,
    val playSources: List<PlaySource>,
    val variants: List<VodVariant>,
    val merged: Boolean,
)

interface VodApi {
    @GET("vod/search")
    suspend fun search(@Query("wd") keyword: String): SearchResponse

    @GET("vod/detail")
    suspend fun detail(
        @Query("sourceId") sourceId: Int,
        @Query("ids") ids: String,
    ): DetailResponse
}
