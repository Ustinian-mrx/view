package com.example.vision_guard

class NcnnVisionEngine {
    var inputSize: Int = 320
        private set
    private var threshold: Float = 0.45f

    val nativeAvailable: Boolean
        get() = isNativeAvailable

    external fun nativeInit(
        paramPath: String,
        binPath: String,
        classesPath: String,
        preprocessPath: String,
        inputSize: Int,
        threshold: Float
    ): Boolean
    external fun nativeDetectYuv420(
        y: ByteArray,
        u: ByteArray,
        v: ByteArray,
        width: Int,
        height: Int,
        rotation: Int,
        bytesPerRow: IntArray,
        bytesPerPixel: IntArray
    ): Array<DetectionNative>
    external fun nativeRelease()

    fun initialize(
        paramPath: String,
        binPath: String,
        classesPath: String,
        preprocessPath: String,
        inputSize: Int,
        threshold: Float
    ) {
        this.inputSize = inputSize
        this.threshold = threshold
        if (!isNativeAvailable) return
        check(nativeInit(paramPath, binPath, classesPath, preprocessPath, inputSize, threshold)) {
            "NCNN engine returned false during initialization"
        }
    }

    fun updateSettings(inputSize: Int, threshold: Float) {
        this.inputSize = inputSize
        this.threshold = threshold
        if (!isNativeAvailable) return
        nativeInit("", "", "", "", inputSize, threshold)
    }

    fun detectYuv420(
        planes: List<ByteArray>,
        width: Int,
        height: Int,
        rotation: Int,
        bytesPerRow: IntArray,
        bytesPerPixel: IntArray
    ): List<Map<String, Any>> {
        // AI辅助生成：Codex.2026-04-28) 统一原生检测输出格式，供 Flutter 展示和播报。
        if (planes.size < 3 || width <= 0 || height <= 0) return emptyList()
        if (!isNativeAvailable) return fallbackObstacleDetection(
            planes[0],
            width,
            height,
            bytesPerRow.firstOrNull() ?: width
        )
        return nativeDetectYuv420(
            planes[0],
            planes[1],
            planes[2],
            width,
            height,
            rotation,
            bytesPerRow,
            bytesPerPixel
        ).filter { it.score >= threshold }
            .map { it.toMap() }
    }

    // AI辅助生成：Codex.2026-04-10) 在原生库不可用时提供基于亮度纹理的障碍物 fallback。
    private fun fallbackObstacleDetection(
        yPlane: ByteArray,
        width: Int,
        height: Int,
        rowStride: Int
    ): List<Map<String, Any>> {
        val scene = sampleRegion(
            yPlane,
            width,
            height,
            rowStride,
            leftRatio = 0.05f,
            topRatio = 0.34f,
            rightRatio = 0.95f,
            bottomRatio = 0.84f
        )
        val candidates = listOf(
            RegionCandidate("left", 0.06f, 0.38f, 0.34f, 0.84f),
            RegionCandidate("center", 0.32f, 0.36f, 0.68f, 0.84f),
            RegionCandidate("right", 0.66f, 0.38f, 0.94f, 0.84f)
        )

        return candidates.mapNotNull { candidate ->
            val stats = sampleRegion(
                yPlane,
                width,
                height,
                rowStride,
                leftRatio = candidate.left,
                topRatio = candidate.top,
                rightRatio = candidate.right,
                bottomRatio = candidate.bottom
            )
            val darkerThanScene = scene.mean - stats.mean
            val hasLargeDarkObject = darkerThanScene > 30f && stats.darkRatio > 0.32f
            val hasStrongTexture = stats.variance > 1600f && stats.darkRatio > 0.28f
            if (!hasLargeDarkObject && !hasStrongTexture) return@mapNotNull null

            val score = (0.52f + (darkerThanScene.coerceAtLeast(0f) / 130f) + stats.darkRatio / 4f)
                .coerceIn(0.55f, 0.90f)
            if (score < threshold) return@mapNotNull null
            val risk = if (hasLargeDarkObject) 0.88f else 0.70f
            val distance = if (stats.darkRatio > 0.42f) 1.0f else 1.8f
            DetectionNative(
                "obstacle",
                score,
                candidate.left,
                candidate.top,
                candidate.right - candidate.left,
                candidate.bottom - candidate.top,
                distance,
                candidate.direction,
                risk
            ).toMap()
        }.sortedByDescending { (it["riskScore"] as Float) }
            .take(3)
    }

    // AI辅助生成：Codex.2026-04-12) 采样画面区域亮度、纹理和暗色比例。
    private fun sampleRegion(
        yPlane: ByteArray,
        width: Int,
        height: Int,
        rowStride: Int,
        leftRatio: Float,
        topRatio: Float,
        rightRatio: Float,
        bottomRatio: Float,
        skipCenter: Boolean = false
    ): RegionStats {
        val left = (width * leftRatio).toInt().coerceIn(0, width - 1)
        val right = (width * rightRatio).toInt().coerceIn(left + 1, width)
        val top = (height * topRatio).toInt().coerceIn(0, height - 1)
        val bottom = (height * bottomRatio).toInt().coerceIn(top + 1, height)
        val centerLeft = (width * 0.30f).toInt()
        val centerRight = (width * 0.70f).toInt()
        var count = 0
        var sum = 0.0
        var sumSq = 0.0
        var dark = 0
        var y = top
        while (y < bottom) {
            var x = left
            val row = y * rowStride
            while (x < right) {
                if (!skipCenter || x < centerLeft || x > centerRight) {
                    val index = row + x
                    if (index in yPlane.indices) {
                        val value = yPlane[index].toInt() and 0xff
                        sum += value
                        sumSq += value * value
                        if (value < 82) dark += 1
                        count += 1
                    }
                }
                x += 4
            }
            y += 4
        }
        if (count == 0) return RegionStats(0f, 0f, 0f)
        val mean = (sum / count).toFloat()
        val variance = (sumSq / count - mean * mean).toFloat()
        return RegionStats(mean, variance, dark.toFloat() / count)
    }

    // AI辅助生成：Codex.2026-04-15) 释放原生推理资源，避免相机退出后残留。
    fun release() {
        if (isNativeAvailable) nativeRelease()
    }

    companion object {
        private val isNativeAvailable: Boolean = try {
            System.loadLibrary("vision_ncnn")
            true
        } catch (_: UnsatisfiedLinkError) {
            false
        }
    }
}

// AI辅助生成：Codex.2026-04-18) 定义 Kotlin 与 C++ JNI 之间的检测结果载体。
data class DetectionNative(
    val className: String,
    val score: Float,
    val left: Float,
    val top: Float,
    val width: Float,
    val height: Float,
    val distanceMeters: Float,
    val direction: String,
    val riskScore: Float
) {
    fun toMap(): Map<String, Any> {
        return mapOf(
            "class" to className,
            "score" to score,
            "box" to listOf(left, top, width, height),
            "distanceMeters" to distanceMeters,
            "direction" to direction,
            "riskScore" to riskScore
        )
    }
}

private data class RegionStats(
    val mean: Float,
    val variance: Float,
    val darkRatio: Float
)

private data class RegionCandidate(
    val direction: String,
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float
)
