package com.follow.clash.services

import android.annotation.SuppressLint
import android.app.Notification.FOREGROUND_SERVICE_IMMEDIATE
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
import android.net.Network
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.Parcel
import android.os.RemoteException
import androidx.core.app.NotificationCompat
import com.follow.clash.BaseServiceInterface
import com.follow.clash.GlobalState
import com.follow.clash.MainActivity
import com.follow.clash.R
import com.follow.clash.TempActivity
import com.follow.clash.extensions.toCIDR
import com.follow.clash.models.AccessControlMode
import com.follow.clash.models.VpnOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

// VPNService + Clash 服务
class FlClashVpnService : VpnService(), BaseServiceInterface {
    override fun onCreate() {
        super.onCreate()
        // 创建时 执行dart：vpnService
        // Dart虚拟机执行 vpnService入口点 -> 通过FFI调用本地库
        GlobalState.initServiceEngine(applicationContext)
    }

    override fun start(options: VpnOptions): Int {
        return with(Builder()) {
            // with(对象)
            // 可以直接访问对象的成员，不需要每次都写对象名
            // 调用对象的方法或访问属性
            if (options.ipv4Address.isNotEmpty()) {
                val cidr = options.ipv4Address.toCIDR()
                addAddress(cidr.address, cidr.prefixLength)
                addRoute("0.0.0.0", 0)
            }
            if (options.ipv6Address.isNotEmpty()) {
                val cidr = options.ipv6Address.toCIDR()
                addAddress(cidr.address, cidr.prefixLength)
                addRoute("::", 0)
            }
            addDnsServer(options.dnsServerAddress)
            setMtu(9000)
            options.accessControl?.let { accessControl ->
                when (accessControl.mode) {
                    AccessControlMode.acceptSelected -> {
                        (accessControl.acceptList + packageName).forEach {
                            addAllowedApplication(it)
                        }
                    }

                    AccessControlMode.rejectSelected -> {
                        (accessControl.rejectList - packageName).forEach {
                            addDisallowedApplication(it)
                        }
                    }
                }
            }
            setSession("FlClash")
            setBlocking(false)
            if (Build.VERSION.SDK_INT >= 29) {
                setMetered(false)
            }
            if (options.allowBypass) {
                allowBypass()
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && options.systemProxy) {
                setHttpProxy(
                    ProxyInfo.buildDirectProxy(
                        "127.0.0.1",
                        options.port,
                        options.bypassDomain
                    )
                )
            }
            // 启动VPNService，获取底层的文件描述符
            establish()?.detachFd()
                ?: throw NullPointerException("Establish VPN rejected by system")
        }
    }

    fun updateUnderlyingNetworks(networks: Array<Network>) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            this.setUnderlyingNetworks(networks)
        }
    }

    override fun stop() {
        stopSelf()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
    }

    private val CHANNEL = "FlClash"

    private val notificationId: Int = 1

    // 两个intent
    // intent：点击通知打开MainActivity
    // stopIntent：停止按钮
    private val notificationBuilder: NotificationCompat.Builder by lazy {
        val intent = Intent(this, MainActivity::class.java)

        val pendingIntent = if (Build.VERSION.SDK_INT >= 31) {
            PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        } else {
            PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT
            )
        }

        val stopIntent = Intent(this, TempActivity::class.java)
        stopIntent.action = "com.follow.clash.action.STOP"
        stopIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)


        val stopPendingIntent = if (Build.VERSION.SDK_INT >= 31) {
            PendingIntent.getActivity(
                this,
                0,
                stopIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        } else {
            PendingIntent.getActivity(
                this,
                0,
                stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT
            )
        }
        with(NotificationCompat.Builder(this, CHANNEL)) {
            setSmallIcon(R.drawable.ic_stat_name)
            setContentTitle("FlClash")
            setContentIntent(pendingIntent)
            setCategory(NotificationCompat.CATEGORY_SERVICE)
            priority = NotificationCompat.PRIORITY_MIN
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                foregroundServiceBehavior = FOREGROUND_SERVICE_IMMEDIATE
            }
            setOngoing(true)
            setShowWhen(false)
            setOnlyAlertOnce(true)
            setAutoCancel(true)
            addAction(0, "Stop", stopPendingIntent);
        }
    }

    // 启动前台服务和通知
    @SuppressLint("ForegroundServiceType", "WrongConstant")
    override fun startForeground(title: String, content: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            var channel = manager?.getNotificationChannel(CHANNEL)
            if (channel == null) {
                channel =
                    NotificationChannel(CHANNEL, "FlClash", NotificationManager.IMPORTANCE_LOW)
                manager?.createNotificationChannel(channel)
            }
        }
        val notification =
            notificationBuilder.setContentTitle(title).setContentText(content).build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(notificationId, notification, FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(notificationId, notification)
        }
    }

    // 应用占用过多内存会被调用
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        GlobalState.getCurrentVPNPlugin()?.requestGc()
    }

    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): FlClashVpnService = this@FlClashVpnService

        override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
            try {
                val isSuccess = super.onTransact(code, data, reply, flags)
                if (!isSuccess) {
                    CoroutineScope(Dispatchers.Main).launch {
                        GlobalState.getCurrentTilePlugin()?.handleStop()
                    }
                }
                return isSuccess
            } catch (e: RemoteException) {
                throw e
            }
        }
    }

    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    override fun onUnbind(intent: Intent?): Boolean {
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        stop()
        super.onDestroy()
    }
}