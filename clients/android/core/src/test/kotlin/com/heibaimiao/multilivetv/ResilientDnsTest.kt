package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.net.ResilientDns
import java.net.InetAddress
import kotlin.test.Test
import kotlin.test.assertEquals

class ResilientDnsTest {
    @Test
    fun prefersIpv4BeforeIpv6() {
        val v4 = InetAddress.getByAddress(byteArrayOf(183.toByte(), 214.toByte(), 156.toByte(), 35))
        val v6 = InetAddress.getByName("::1")
        assertEquals(listOf(v4, v6), ResilientDns.preferIpv4(listOf(v6, v4)))
        assertEquals(listOf(v4, v6), ResilientDns.preferIpv4(listOf(v4, v6)))
    }

    @Test
    fun keepsSingleFamilyOrder() {
        val a = InetAddress.getByAddress(byteArrayOf(1, 2, 3, 4))
        val b = InetAddress.getByAddress(byteArrayOf(5, 6, 7, 8))
        assertEquals(listOf(a, b), ResilientDns.preferIpv4(listOf(a, b)))
    }
}
