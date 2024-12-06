package com.follow.clash.plugins

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.IBinder
import androidx.core.content.getSystemService
import com.follow.clash.BaseServiceInterface
import com.follow.clash.GlobalState
import com.follow.clash.RunState
import com.follow.clash.extensions.getProtocol
import com.follow.clash.extensions.resolveDns
import com.follow.clash.services.FlClashService
import com.follow.clash.services.FlClashVpnService
import com.google.gson.Gson
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.InetSocketAddress
import kotlin.concurrent.withLock
import com.follow.clash.models.Process
import com.follow.clash.models.VpnOptions

// start：
// stop：
// setProtect：
// startForeground：
// resolverProcess：

// 网络状态监控，并回调到Dart层
class VpnPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var flutterMethodChannel: MethodChannel
    private lateinit var context: Context
    private var flClashService: BaseServiceInterface? = null
    private lateinit var options: VpnOptions
    private lateinit var scope: CoroutineScope

    // 获取系统服务 ConnectivityManager 用于管理网络连接
    private val connectivity by lazy {
        context.getSystemService<ConnectivityManager>()
    }

    // bindService后，用于与服务交互
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(className: ComponentName, service: IBinder) {
            flClashService = when (service) {
                is FlClashVpnService.LocalBinder -> service.getService()
                is FlClashService.LocalBinder -> service.getService()
                else -> throw Exception("invalid binder")
            }
            start()
        }

        override fun onServiceDisconnected(arg: ComponentName) {
            flClashService = null
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        scope = CoroutineScope(Dispatchers.Default)
        context = flutterPluginBinding.applicationContext
        scope.launch {
            registerNetworkCallback()
        }
        flutterMethodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "vpn")
        flutterMethodChannel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        unRegisterNetworkCallback()
        flutterMethodChannel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val data = call.argument<String>("data")
                options = Gson().fromJson(data, VpnOptions::class.java)
                when (options.enable) {
                    true -> handleStartVpn()
                    false -> start()
                }
                result.success(true)
            }

            "stop" -> {
                stop()
                result.success(true)
            }

            "setProtect" -> {
                val fd = call.argument<Int>("fd")
                if (fd != null) {
                    if (flClashService is FlClashVpnService) {
                        (flClashService as FlClashVpnService).protect(fd)
                    }
                    result.success(true)
                } else {
                    result.success(false)
                }
            }

            "startForeground" -> {
                val title = call.argument<String>("title") as String
                val content = call.argument<String>("content") as String
                startForeground(title, content)
                result.success(true)
            }

            "resolverProcess" -> {
                val data = call.argument<String>("data")
                val process =
                    if (data != null) Gson().fromJson(
                        data,
                        Process::class.java
                    ) else null
                val metadata = process?.metadata
                if (metadata == null) {
                    result.success(null)
                    return
                }
                val protocol = metadata.getProtocol()
                if (protocol == null) {
                    result.success(null)
                    return
                }
                scope.launch {
                    withContext(Dispatchers.Default) {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                            result.success(null)
                            return@withContext
                        }
                        val src = InetSocketAddress(metadata.sourceIP, metadata.sourcePort)
                        val dst = InetSocketAddress(
                            metadata.destinationIP.ifEmpty { metadata.host },
                            metadata.destinationPort
                        )
                        val uid = try {
                            connectivity?.getConnectionOwnerUid(protocol, src, dst)
                        } catch (_: Exception) {
                            null
                        }
                        if (uid == null || uid == -1) {
                            result.success(null)
                            return@withContext
                        }
                        val packages = context.packageManager?.getPackagesForUid(uid)
                        result.success(packages?.first())
                    }
                }
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    private fun handleStartVpn() {
        GlobalState.getCurrentAppPlugin()?.requestVpnPermission(context) {
            start()
        }
    }

    fun requestGc() {
        flutterMethodChannel.invokeMethod("gc", null)
    }

    val networks = mutableSetOf<Network>()

    fun onUpdateNetwork() {
        val dns = networks.flatMap { network ->
            connectivity?.resolveDns(network) ?: emptyList()
        }
            .toSet()
            .joinToString(",")
        scope.launch {
            withContext(Dispatchers.Main) {
                flutterMethodChannel.invokeMethod("dnsChanged", dns)
            }
        }
//        if (flClashService is FlClashVpnService) {
//            val network = networks.maxByOrNull { net ->
//                connectivity?.getNetworkCapabilities(net)?.let { cap ->
//                    TRANSPORT_PRIORITY.indexOfFirst { cap.hasTransport(it) }
//                } ?: -1
//            }
//            network?.let {
//                (flClashService as FlClashVpnService).updateUnderlyingNetworks(arrayOf(network))
//            }
//        }
    }

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            networks.add(network)
            onUpdateNetwork()
        }

        override fun onLost(network: Network) {
            networks.remove(network)
            onUpdateNetwork()
        }
    }

    private val request = NetworkRequest.Builder().apply {
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
    }.build()

    private fun registerNetworkCallback() {
        networks.clear()
        connectivity?.registerNetworkCallback(request, callback)
    }

    private fun unRegisterNetworkCallback() {
        connectivity?.unregisterNetworkCallback(callback)
        networks.clear()
        onUpdateNetwork()
    }

    private fun startForeground(title: String, content: String) {
        GlobalState.runLock.withLock {
            if (GlobalState.runState.value != RunState.START) return
            flClashService?.startForeground(title, content)
        }
    }

    private fun start() {
        if (flClashService == null) {
            bindService()
            return
        }
        GlobalState.runLock.withLock {
            if (GlobalState.runState.value == RunState.START) return
            GlobalState.runState.value = RunState.START
            val fd = flClashService?.start(options)
            flutterMethodChannel.invokeMethod(
                "started",
                fd
            )
        }
    }

    fun stop() {
        GlobalState.runLock.withLock {
            if (GlobalState.runState.value == RunState.STOP) return
            GlobalState.runState.value = RunState.STOP
            flClashService?.stop()
        }
        GlobalState.destroyServiceEngine()
    }

    private fun bindService() {
        val intent = when (options.enable) {
            true -> Intent(context, FlClashVpnService::class.java)
            false -> Intent(context, FlClashService::class.java)
        }
        context.bindService(intent, connection, Context.BIND_AUTO_CREATE)
    }

}