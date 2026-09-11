package com.heibaimiao.multilivetv.source

import com.heibaimiao.multilivetv.maccms.VodItemRaw
import com.heibaimiao.multilivetv.model.Source

data class SourceMovie(
    val sourceId: String,
    val numericSourceId: Int,
    val sourceMovieId: String,
    val title: String,
    val year: String,
    val poster: String,
    val remarks: String,
    val area: String,
    val genre: String,
    val blurb: String,
    val content: String,
    val actors: List<String>,
    val director: String,
    val typeId: Int,
    val typeName: String,
    val playFrom: String,
    val playURL: String,
    val updatedAt: Int,
) {
    fun toVodItemRaw(): VodItemRaw = VodItemRaw(
        vodId = sourceMovieId,
        vodName = title,
        vodPic = poster,
        vodRemarks = remarks,
        vodYear = year,
        vodArea = area,
        vodClass = genre,
        vodBlurb = blurb,
        vodContent = content,
        vodActor = actors.joinToString(","),
        vodDirector = director,
        vodPlayFrom = playFrom,
        vodPlayURL = playURL,
        typeId = typeId,
        typeName = typeName,
        vodTime = updatedAt,
    )
}

data class SourcePage(
    val page: Int,
    val pageCount: Int,
    val total: Int,
    val list: List<SourceMovie>,
)

object MacCMSSourceParser {
    fun parseActors(raw: String): List<String> {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return emptyList()
        return trimmed.split(Regex("""[,，/、|]""")).map { it.trim() }.filter { it.isNotEmpty() }
    }

    fun toSourceMovie(source: Source, raw: VodItemRaw): SourceMovie = SourceMovie(
        sourceId = source.sourceId,
        numericSourceId = source.numericId,
        sourceMovieId = raw.vodId,
        title = raw.vodName,
        year = raw.vodYear,
        poster = raw.vodPic,
        remarks = raw.vodRemarks,
        area = raw.vodArea,
        genre = raw.vodClass,
        blurb = raw.vodBlurb,
        content = raw.vodContent,
        actors = parseActors(raw.vodActor),
        director = raw.vodDirector.trim(),
        typeId = raw.typeId,
        typeName = raw.typeName,
        playFrom = raw.vodPlayFrom,
        playURL = raw.vodPlayURL,
        updatedAt = raw.vodTime,
    )
}
