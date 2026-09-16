package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.net.RequestFailure
import com.heibaimiao.multilivetv.net.VodClientException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals

class RequestFailureTest {
    @Test
    fun httpsUrlInMessage_is_not_classified_as_http_status_error() {
        val shown = RequestFailure.userFacingMessage(
            Exception("unexpected end of stream on https://cdn.example.com/index"),
        )
        assertNotEquals("服务器响应异常，请稍后重试", shown)
    }

    @Test
    fun connectFailureWithHttpsUrl_is_connection_error() {
        assertEquals(
            "连接失败，请稍后重试",
            RequestFailure.userFacingMessage(Exception("Failed to connect to https://example.com")),
        )
    }

    @Test
    fun http403_is_server_error() {
        assertEquals(
            "服务器响应异常，请稍后重试",
            RequestFailure.userFacingMessage(VodClientException("HTTP 403")),
        )
    }

    @Test
    fun http502_is_server_error() {
        assertEquals(
            "服务器响应异常，请稍后重试",
            RequestFailure.userFacingMessage(VodClientException("HTTP 502")),
        )
    }

    @Test
    fun aggregatedSourceFailure_keeps_original_message() {
        assertEquals(
            "无法连接资源站，请检查网络后重试",
            RequestFailure.userFacingMessage(VodClientException("无法连接资源站，请检查网络后重试")),
        )
    }
}
