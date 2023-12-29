package com.hiddify.hiddify.bg

import android.net.DnsResolver
import android.os.Build
import android.os.CancellationSignal
import android.system.ErrnoException
import androidx.annotation.RequiresApi
import com.hiddify.hiddify.ktx.tryResumeWithException
import io.nekohasekai.libbox.ExchangeContext
import io.nekohasekai.libbox.LocalDNSTransport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.asExecutor
import kotlinx.coroutines.runBlocking
import java.net.InetAddress
import java.net.UnknownHostException
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

object LocalResolver : LocalDNSTransport {

    private const val RCODE_NXDOMAIN = 3

    override fun raw(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    override fun exchange(ctx: ExchangeContext, message: ByteArray) {
        return runBlocking {
            suspendCoroutine { continuation ->
                val signal = CancellationSignal()
                ctx.onCancel(signal::cancel)
                val callback = object : DnsResolver.Callback<ByteArray> {
                    override fun onAnswer(answer: ByteArray, rcode: Int) {
                        if (rcode == 0) {
                            ctx.rawSuccess(answer)
                        } else {
                            ctx.errorCode(rcode)
                        }
                        continuation.resume(Unit)
                    }

                    override fun onError(error: DnsResolver.DnsException) {
                        when (val cause = error.cause) {
                            is ErrnoException -> {
                                ctx.errnoCode(cause.errno)
                                continuation.resume(Unit)
                                return
                            }
                        }
                        continuation.tryResumeWithException(error)
                    }
                }
                DnsResolver.getInstance().rawQuery(
                    DefaultNetworkMonitor.defaultNetwork,
                    message,
                    DnsResolver.FLAG_NO_RETRY,
                    Dispatchers.IO.asExecutor(),
                    signal,
                    callback
                )
            }
        }
    }

    override fun lookup(ctx: ExchangeContext, network: String, domain: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return runBlocking {
                suspendCoroutine { continuation ->
                    val signal = CancellationSignal()
                    ctx.onCancel(signal::cancel)
                    val callback = object : DnsResolver.Callback<Collection<InetAddress>> {
                        @Suppress("ThrowableNotThrown")
                        override fun onAnswer(answer: Collection<InetAddress>, rcode: Int) {
                            if (rcode == 0) {
                                ctx.success((answer as Collection<InetAddress?>).mapNotNull { it?.hostAddress }
                                    .joinToString("\n"))
                            } else {
                                ctx.errorCode(rcode)
                            }
                            continuation.resume(Unit)
                        }

                        override fun onError(error: DnsResolver.DnsException) {
                            when (val cause = error.cause) {
                                is ErrnoException -> {
                                    ctx.errnoCode(cause.errno)
                                    continuation.resume(Unit)
                                    return
                                }
                            }
                            continuation.tryResumeWithException(error)
                        }
                    }
                    val type = when {
                        network.endsWith("4") -> DnsResolver.TYPE_A
                        network.endsWith("6") -> DnsResolver.TYPE_AAAA
                        else -> null
                    }
                    if (type != null) {
                        DnsResolver.getInstance().query(
                            DefaultNetworkMonitor.defaultNetwork,
                            domain,
                            type,
                            DnsResolver.FLAG_NO_RETRY,
                            Dispatchers.IO.asExecutor(),
                            signal,
                            callback
                        )
                    } else {
                        DnsResolver.getInstance().query(
                            DefaultNetworkMonitor.defaultNetwork,
                            domain,
                            DnsResolver.FLAG_NO_RETRY,
                            Dispatchers.IO.asExecutor(),
                            signal,
                            callback
                        )
                    }
                }
            }
        } else {
            val underlyingNetwork =
                DefaultNetworkMonitor.defaultNetwork ?: error("upstream network not found")
            val answer = try {
                underlyingNetwork.getAllByName(domain)
            } catch (e: UnknownHostException) {
                ctx.errorCode(RCODE_NXDOMAIN)
                return
            }
            ctx.success(answer.mapNotNull { it.hostAddress }.joinToString("\n"))
        }
    }
}