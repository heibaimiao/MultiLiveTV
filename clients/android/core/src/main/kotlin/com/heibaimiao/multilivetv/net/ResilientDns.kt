package com.heibaimiao.multilivetv.net

import okhttp3.Dns
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.dnsoverhttps.DnsOverHttps
import java.net.InetAddress
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit

/**
 * System DNS first; on failure fall back to DoH so emulators / broken resolvers still work.
 */
object ResilientDns : Dns {
    private val bootstrapClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(NetworkConfig.CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(NetworkConfig.CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .callTimeout(NetworkConfig.CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .cache(null)
            .build()
    }

    private val doh: Dns by lazy {
        DnsOverHttps.Builder()
            .client(bootstrapClient)
            .url("https://dns.alidns.com/dns-query".toHttpUrl())
            .bootstrapDnsHosts(
                InetAddress.getByName("223.5.5.5"),
                InetAddress.getByName("223.6.6.6"),
            )
            .includeIPv6(false)
            .build()
    }

    override fun lookup(hostname: String): List<InetAddress> {
        val resolved = try {
            val system = Dns.SYSTEM.lookup(hostname)
            if (system.isNotEmpty()) system else lookupDoh(hostname)
        } catch (_: UnknownHostException) {
            lookupDoh(hostname)
        }
        return preferIpv4(resolved)
    }

    fun preferIpv4(addresses: List<InetAddress>): List<InetAddress> =
        addresses.sortedBy { address -> if (address.address.size == 4) 0 else 1 }

    private fun lookupDoh(hostname: String): List<InetAddress> = try {
        doh.lookup(hostname)
    } catch (error: UnknownHostException) {
        throw error
    } catch (error: Exception) {
        throw UnknownHostException("DoH lookup failed for $hostname: ${error.message}")
    }
}
