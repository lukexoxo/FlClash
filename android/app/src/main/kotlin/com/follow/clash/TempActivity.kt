package com.follow.clash

import android.app.Activity
import android.os.Bundle

// 无界面，用来后台执行方法
// 根据传入的 Intent 的 action 字段，决定调用TilePlugin
class TempActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        when (intent.action) {
            "com.follow.clash.action.START" -> {
                GlobalState.getCurrentTilePlugin()?.handleStart()
            }

            "com.follow.clash.action.STOP" -> {
                GlobalState.getCurrentTilePlugin()?.handleStop()
            }
        }
        // 结束当前的活动并从任务栈中移除该活动
        finishAndRemoveTask()
    }
}