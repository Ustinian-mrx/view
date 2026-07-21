package com.example.vision_guard

import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val engine = NcnnVisionEngine()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // AI辅助生成：Codex.2026-04-28) 建立 Dart 到 Kotlin 的方法通道分发入口。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "vision_guard/ncnn"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> initialize(call, result)
                "updateSettings" -> updateSettings(call, result)
                "detectYuv420" -> detectYuv420(call, result)
                "vibrateAlert" -> {
                    vibrateAlert(call.argument<Boolean>("strong") ?: true)
                    result.success(null)
                }
                "dispose" -> {
                    engine.release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // AI辅助生成：Codex.2026-04-02) 兼容不同 Android 版本的震动提醒调用。
    private fun vibrateAlert(strong: Boolean) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (!vibrator.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val pattern = if (strong) longArrayOf(0, 180) else longArrayOf(0, 90)
            val amplitudes = if (strong) intArrayOf(0, 180) else intArrayOf(0, 120)
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, amplitudes, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(if (strong) 180L else 90L)
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        try {
            // AI辅助生成：Codex.2026-04-28) 复制 Flutter 模型资产到缓存后交给原生推理引擎。
            val paramAsset = call.argument<String>("paramAsset") ?: ""
            val binAsset = call.argument<String>("binAsset") ?: ""
            val classesAsset = call.argument<String>("classesAsset") ?: ""
            val preprocessAsset = call.argument<String>("preprocessAsset") ?: ""
            val inputSize = call.argument<Int>("inputSize") ?: 320
            val threshold = call.argument<Double>("confidenceThreshold") ?: 0.45
            val paramPath = copyFlutterAssetToCache(paramAsset)
            val binPath = copyFlutterAssetToCache(binAsset)
            val classesPath = copyFlutterAssetToCache(classesAsset)
            val preprocessPath = copyFlutterAssetToCache(preprocessAsset)
            engine.initialize(
                paramPath,
                binPath,
                classesPath,
                preprocessPath,
                inputSize,
                threshold.toFloat()
            )
            result.success(null)
        } catch (error: Throwable) {
            result.error("NCNN_INIT_FAILED", error.message, null)
        }
    }

    // AI辅助生成：Codex.2026-04-05) 接收 Flutter 设置页更新并传递给推理引擎。
    private fun updateSettings(call: MethodCall, result: MethodChannel.Result) {
        val inputSize = call.argument<Int>("inputSize") ?: 320
        val threshold = call.argument<Double>("confidenceThreshold") ?: 0.45
        engine.updateSettings(inputSize, threshold.toFloat())
        result.success(null)
    }

    @Suppress("UNCHECKED_CAST")
    // AI辅助生成：Codex.2026-04-08) 接收相机三平面数据并返回统一检测帧。
    private fun detectYuv420(call: MethodCall, result: MethodChannel.Result) {
        try {
            val startedAt = SystemClock.elapsedRealtimeNanos()
            val planes = call.argument<List<ByteArray>>("planes") ?: emptyList()
            val width = call.argument<Int>("width") ?: 0
            val height = call.argument<Int>("height") ?: 0
            val rotation = call.argument<Int>("rotation") ?: 0
            val bytesPerRow = call.argument<List<Int>>("bytesPerRow") ?: emptyList()
            val bytesPerPixel = call.argument<List<Int>>("bytesPerPixel") ?: emptyList()

            val detections = engine.detectYuv420(
                planes,
                width,
                height,
                rotation,
                bytesPerRow.toIntArray(),
                bytesPerPixel.toIntArray()
            )
            val latencyMs = ((SystemClock.elapsedRealtimeNanos() - startedAt) / 1_000_000).toInt()
            result.success(
                mapOf(
                    "timestamp" to System.currentTimeMillis(),
                    "latencyMs" to latencyMs,
                    "inputWidth" to engine.inputSize,
                    "inputHeight" to engine.inputSize,
                    "detections" to detections
                )
            )
        } catch (error: Throwable) {
            result.error("NCNN_DETECT_FAILED", error.message, null)
        }
    }

    private fun copyFlutterAssetToCache(assetName: String): String {
        val loader = FlutterInjector.instance().flutterLoader()
        val key = loader.getLookupKeyForAsset(assetName)
        val target = File(cacheDir, assetName.substringAfterLast('/'))
        assets.open(key).use { input ->
            FileOutputStream(target).use { output -> input.copyTo(output) }
        }
        return target.absolutePath
    }
}
