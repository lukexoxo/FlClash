
package com.follow.clash.plugins

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// 开关磁贴插件，点击磁贴时：handleStart、handleStop、handleDetached
// 调用Dart代码
// MethodChannel：原生调用Dart
// onMethodCall：Dart调用原生
class TilePlugin(private val onStart: (() -> Unit)? = null, private val onStop: (() -> Unit)? = null) : FlutterPlugin,
    MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel

    // 插件绑定到 Flutter 引擎
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "tile")
        channel.setMethodCallHandler(this)
    }

    // 插件从 Flutter 引擎解绑
    // 用户退出应用，或应用进程被杀死
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        handleDetached()
        channel.setMethodCallHandler(null)
    }

    fun handleStart() {
        onStart?.let { it() }
        channel.invokeMethod("start", null)
    }

    fun handleStop() {
        channel.invokeMethod("stop", null)
        onStop?.let { it() }
    }

    private fun handleDetached() {
        channel.invokeMethod("detached", null)
    }


    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {}
}