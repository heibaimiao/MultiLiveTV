package com.heibaimiao.multilivetv.display

import com.heibaimiao.multilivetv.home.HomeFeed

object VodDisplayFormatter {
    private val ymdPattern = Regex("""(?<!\d)(20\d{2})(\d{2})(\d{2})(?!\d)""")
    private val breakTagPattern = Regex("""(?i)<br\s*/?>|</(?:p|div|li|h[1-6]|tr)>""")
    private val htmlTagPattern = Regex("""<[^>]+>""")
    private val whitespacePattern = Regex("""\s+""")

    fun plainText(raw: String?): String? {
        if (raw == null) return null
        var text = breakTagPattern.replace(raw, " ")
        text = htmlTagPattern.replace(text, "")
        text = decodeHtmlEntities(text)
        text = whitespacePattern.replace(text, " ").trim()
        return text.ifEmpty { null }
    }

    fun formatRemarks(raw: String?): String? {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        return replaceEmbeddedDates(trimmed)
    }

    fun genreLine(typeName: String?, year: String?): String? {
        val parts = mutableListOf<String>()
        if (!typeName.isNullOrEmpty()) parts += typeName
        val normalizedYear = HomeFeed.normalizeYear(year)
        if (normalizedYear.isNotEmpty()) parts += normalizedYear
        return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
    }

    private fun decodeHtmlEntities(text: String): String {
        if (!text.contains("&")) return text
        return text
            .replace("&nbsp;", " ")
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
            .replace("&apos;", "'")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&amp;", "&")
    }

    private fun replaceEmbeddedDates(text: String): String {
        return ymdPattern.replace(text) { match ->
            val month = match.groupValues[2].toIntOrNull() ?: return@replace match.value
            val day = match.groupValues[3].toIntOrNull() ?: return@replace match.value
            if (month !in 1..12 || day !in 1..31) match.value else "$month-$day"
        }
    }
}
