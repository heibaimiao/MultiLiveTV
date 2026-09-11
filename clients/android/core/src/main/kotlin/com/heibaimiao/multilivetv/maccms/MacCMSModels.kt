package com.heibaimiao.multilivetv.maccms

import com.heibaimiao.multilivetv.model.VodItem
import com.heibaimiao.multilivetv.model.VodVariant
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.LocalDateTime
import java.time.ZoneId

data class VodTypeRaw(
    val typeId: Int,
    val typeName: String,
)

data class VodItemRaw(
    val vodId: String,
    val vodName: String,
    val vodPic: String,
    val vodRemarks: String,
    val vodYear: String,
    val vodArea: String,
    val vodClass: String,
    val vodBlurb: String,
    val vodContent: String,
    val vodActor: String = "",
    val vodDirector: String = "",
    val vodPlayFrom: String,
    val vodPlayURL: String,
    val typeId: Int,
    val typeName: String,
    val vodTime: Int,
) {
    fun toVodItem(variants: List<VodVariant>? = null, primarySourceId: Int? = null): VodItem = VodItem(
        vodId = vodId,
        vodName = vodName,
        vodPic = vodPic,
        vodRemarks = vodRemarks.ifEmpty { null },
        vodBlurb = vodBlurb.ifEmpty { null },
        vodContent = vodContent.ifEmpty { null },
        typeName = typeName.ifEmpty { null },
        vodClass = vodClass.ifEmpty { null },
        vodYear = vodYear.ifEmpty { null },
        variants = variants,
        primarySourceId = primarySourceId,
        vodTime = vodTime,
    )

    fun withVodTime(time: Int): VodItemRaw = copy(vodTime = time)
}

data class MacCMSListResponse(
    val code: Int,
    val msg: String,
    val page: Int,
    val pageCount: Int,
    val limit: String,
    val total: Int,
    val list: List<VodItemRaw>,
    val types: List<VodTypeRaw>,
)

data class MacCMSDetailResponse(
    val code: Int,
    val msg: String,
    val list: List<VodItemRaw>,
)

data class MergeableVodItem(
    val item: VodItemRaw,
    val sourceId: Int,
    val sourceName: String,
)

object MacCMSJsonParser {
    fun parseList(root: JsonObject): MacCMSListResponse = MacCMSListResponse(
        code = flexInt(root["code"]) ?: 0,
        msg = root["msg"]?.jsonPrimitive?.contentOrNull.orEmpty(),
        page = flexInt(root["page"]) ?: 1,
        pageCount = flexInt(root["pagecount"]) ?: 1,
        limit = flexString(root["limit"]).orEmpty(),
        total = flexInt(root["total"]) ?: 0,
        list = parseVodItems(root["list"]),
        types = parseTypes(root["class"]),
    )

    fun parseDetail(root: JsonObject): MacCMSDetailResponse = MacCMSDetailResponse(
        code = flexInt(root["code"]) ?: 0,
        msg = root["msg"]?.jsonPrimitive?.contentOrNull.orEmpty(),
        list = parseVodItems(root["list"]),
    )

    fun parseVodTime(value: JsonElement?): Int = when (value) {
        null -> 0
        is JsonPrimitive -> {
            val intValue = flexInt(value)
            if (intValue != null) normalizeUnix(intValue) else parseDateTimeString(value.content.trim())
        }
        else -> 0
    }

    private fun parseVodItems(value: JsonElement?): List<VodItemRaw> {
        val array = value as? JsonArray ?: return emptyList()
        return array.mapNotNull { element ->
            val obj = element as? JsonObject ?: return@mapNotNull null
            parseVodItem(obj)
        }
    }

    private fun parseTypes(value: JsonElement?): List<VodTypeRaw> {
        val array = value as? JsonArray ?: return emptyList()
        return array.mapNotNull { element ->
            val obj = element as? JsonObject ?: return@mapNotNull null
            val typeId = flexInt(obj["type_id"]) ?: return@mapNotNull null
            val typeName = obj["type_name"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            VodTypeRaw(typeId, typeName)
        }
    }

    private fun parseVodItem(dict: JsonObject): VodItemRaw? {
        val vodName = dict["vod_name"]?.jsonPrimitive?.contentOrNull ?: return null
        val vodTime = parseVodTime(dict["vod_time"])
        val vodTimeAdd = parseVodTime(dict["vod_time_add"])
        return VodItemRaw(
            vodId = flexString(dict["vod_id"]).orEmpty(),
            vodName = vodName,
            vodPic = dict["vod_pic"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            vodRemarks = dict["vod_remarks"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            vodYear = dict["vod_year"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            vodArea = dict["vod_area"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            vodClass = dict["vod_class"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            vodBlurb = dict["vod_blurb"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            vodContent = dict["vod_content"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            vodActor = dict["vod_actor"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            vodDirector = dict["vod_director"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            vodPlayFrom = dict["vod_play_from"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            vodPlayURL = dict["vod_play_url"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            typeId = flexInt(dict["type_id"]) ?: 0,
            typeName = dict["type_name"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            vodTime = if (vodTime > 0) vodTime else vodTimeAdd,
        )
    }

    private fun normalizeUnix(value: Int): Int = when {
        value <= 0 -> 0
        value > 10_000_000_000 -> value / 1000
        else -> value
    }

    private fun parseDateTimeString(raw: String): Int {
        val parts = Regex("""\d+""").findAll(raw).map { it.value.toInt() }.toList()
        if (parts.size < 3) return 0
        return try {
            val date = LocalDateTime.of(
                parts[0],
                parts[1],
                parts[2],
                parts.getOrElse(3) { 0 },
                parts.getOrElse(4) { 0 },
                parts.getOrElse(5) { 0 },
            )
            date.atZone(ZoneId.of("Asia/Shanghai")).toEpochSecond().toInt()
        } catch (_: Exception) {
            0
        }
    }

    fun flexString(value: JsonElement?): String? = when (value) {
        null -> null
        is JsonPrimitive -> if (value.isString) value.content else value.content
        else -> null
    }

    fun flexInt(value: JsonElement?): Int? = when (value) {
        null -> null
        is JsonPrimitive -> value.content.toDoubleOrNull()?.toInt()
        else -> null
    }
}
