package com.follow.clash

import android.content.Context
import androidx.lifecycle.MutableLiveData
import com.follow.clash.plugins.AppPlugin
import com.follow.clash.plugins.ServicePlugin
import com.follow.clash.plugins.VpnPlugin
import com.follow.clash.plugins.TilePlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

enum class RunState {
    START,
    PENDING,
    STOP
}


// object 用于创建单例对象或静态工具类
// 不需要手动实例化、自动是一个单例对象
object GlobalState {

    private val lock = ReentrantLock()
    val runLock = ReentrantLock()

    val runState: MutableLiveData<RunState> = MutableLiveData<RunState>(RunState.STOP)

    // 在MainActivity中初始化
    // FlutterEngine会创建一个独立的Dart虚拟机，用于执行Dart代码，destroy后虚拟机停止运行。
    var flutterEngine: FlutterEngine? = null
    private var serviceEngine: FlutterEngine? = null

    fun getCurrentAppPlugin(): AppPlugin? {
        val currentEngine = if (flutterEngine != null) flutterEngine else serviceEngine
        return currentEngine?.plugins?.get(AppPlugin::class.java) as AppPlugin?
    }

    fun getCurrentTilePlugin(): TilePlugin? {
        val currentEngine = if (flutterEngine != null) flutterEngine else serviceEngine
        return currentEngine?.plugins?.get(TilePlugin::class.java) as TilePlugin?
    }

    fun getCurrentVPNPlugin(): VpnPlugin? {
        return serviceEngine?.plugins?.get(VpnPlugin::class.java) as VpnPlugin?
    }

    fun destroyServiceEngine() {
        serviceEngine?.destroy()
        serviceEngine = null
    }

    // 初始化VPNService -> 指定Dart入口点
    fun initServiceEngine(context: Context) {
        if (serviceEngine != null) return
        lock.withLock {
            destroyServiceEngine()
            serviceEngine = FlutterEngine(context)
            serviceEngine?.plugins?.add(VpnPlugin())
            serviceEngine?.plugins?.add(AppPlugin())
            serviceEngine?.plugins?.add(TilePlugin())
            serviceEngine?.plugins?.add(ServicePlugin())
            val vpnService = DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "vpnService"
            )
            serviceEngine?.dartExecutor?.executeDartEntrypoint(
                vpnService,
            )
        }
    }
}


