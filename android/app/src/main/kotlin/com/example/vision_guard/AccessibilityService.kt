package com.example.vision_guard

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager

// TalkBack 无障碍服务：处理屏幕阅读器交互
class AccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "VisionGuardAccessibility"
        private var instance: AccessibilityService? = null

        fun getInstance(): AccessibilityService? = instance
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this

        val info = serviceInfo
        info.eventTypes = AccessibilityEvent.TYPES_ALL_MASK
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_SPOKEN
        info.notificationTimeout = 100
        info.flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        serviceInfo = info

        Log.i(TAG, "TalkBack 无障碍服务已连接")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 处理 TalkBack 事件
        event?.let {
            when (it.eventType) {
                AccessibilityEvent.TYPE_VIEW_CLICKED -> {
                    Log.d(TAG, "用户点击: ${it.className}")
                }
                AccessibilityEvent.TYPE_VIEW_FOCUSED -> {
                    Log.d(TAG, "焦点移动: ${it.className}")
                }
                AccessibilityEvent.TYPE_ANNOUNCEMENT -> {
                    Log.d(TAG, "语音播报: ${it.text}")
                }
            }
        }
    }

    override fun onInterrupt() {
        Log.i(TAG, "TalkBack 无障碍服务已中断")
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
        Log.i(TAG, "TalkBack 无障碍服务已销毁")
    }

    // 发送 TalkBack 播报
    fun announceForAccessibility(text: String) {
        val event = AccessibilityEvent.obtain(AccessibilityEvent.TYPE_ANNOUNCEMENT).apply {
            this.text.add(text)
        }
        val manager = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        manager.sendAccessibilityEvent(event)
        event.recycle()
    }
}
