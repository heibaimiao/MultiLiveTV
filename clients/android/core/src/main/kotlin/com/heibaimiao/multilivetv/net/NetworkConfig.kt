package com.heibaimiao.multilivetv.net

object NetworkConfig {
    const val USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    const val CONNECT_TIMEOUT_SECONDS = 5L
    const val REQUEST_TIMEOUT_SECONDS = 8L
}

object RemoteMediaURL {
    fun parse(string: String): String? {
        var trimmed = string.trim()
        if (trimmed.isEmpty()) return null
        if (trimmed.startsWith("//")) trimmed = "https:$trimmed"
        return if (isUsable(trimmed)) trimmed else null
    }

    private fun isUsable(url: String): Boolean {
        val lower = url.lowercase()
        if (!lower.startsWith("http://") && !lower.startsWith("https://")) return false
        val withoutScheme = url.substringAfter("://")
        val host = withoutScheme.substringBefore("/").substringBefore("?")
        return host.isNotEmpty()
    }
}

object RequestFailure {
    fun userFacingMessage(error: Throwable): String {
        val message = error.message.orEmpty().lowercase()
        return when {
            "timeout" in message || "timed out" in message -> "请求超时，请检查网络后重试"
            "unable to resolve" in message || "unknownhost" in message -> "无法连接服务器，请稍后重试"
            "connect" in message || "connection" in message -> "连接失败，请稍后重试"
            "ssl" in message || "certificate" in message || "tls" in message -> "安全连接失败，请稍后重试"
            "http" in message || "unexpected code" in message -> "服务器响应异常，请稍后重试"
            error.message?.isNotBlank() == true && error is VodClientException -> error.message!!
            else -> "加载失败，请稍后重试"
        }
    }
}

class VodClientException(message: String) : Exception(message)
