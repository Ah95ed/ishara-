package com.Ishara.iq.ishara.camera

import android.os.SystemClock
import android.util.Log
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/**
 * بيانات تشخيصية لأداء الكاميرا والتحليل (CameraPerformanceMetrics)
 */
data class CameraPerformanceMetrics(
    val requestedFps: Int,
    val cameraDeliveredFps: Double,
    val landmarkProcessedFps: Double,
    val droppedCameraFrames: Long,
    val replacedPendingFrames: Long,
    val averageFrameAgeMs: Double,
    val averageLandmarkProcessingMs: Double,
    val maxLandmarkProcessingMs: Long
) {
    fun toMap(): Map<String, Any> {
        return mapOf(
            "requestedFps" to requestedFps,
            "cameraDeliveredFps" to cameraDeliveredFps,
            "landmarkProcessedFps" to landmarkProcessedFps,
            "droppedCameraFrames" to droppedCameraFrames,
            "replacedPendingFrames" to replacedPendingFrames,
            "averageFrameAgeMs" to averageFrameAgeMs,
            "averageLandmarkProcessingMs" to averageLandmarkProcessingMs,
            "maxLandmarkProcessingMs" to maxLandmarkProcessingMs
        )
    }
}

/**
 * محلل إطارات الكاميرا (CameraFrameAnalyzer)
 * يضمن:
 * 1. استراتيجية Latest-frame-wins وعدم تراكم Backlog في الذاكرة.
 * 2. إغلاق الـ ImageProxy دائماً داخل كتلة try/finally دون أي تسريب.
 * 3. قياس معدل إطارات الكاميرا الفعلي (cameraDeliveredFps) ومعدل المعالجة (landmarkProcessedFps).
 * 4. حساب عمر الفريم (Frame Age) وتخطي الإطارات المتأخرة.
 */
class CameraFrameAnalyzer(
    private var requestedFps: Int = 30,
    private val onFrameReceived: (ImageProxy, Long) -> Unit
) : ImageAnalysis.Analyzer {

    companion object {
        private const val TAG = "CameraFrameAnalyzer"
        private const val MAX_STALE_FRAME_AGE_MS = 150L // سقف عمر الفريم لمنع معالجة إطارات متأخرة
    }

    // مقاييس الإطارات
    private val deliveredFramesCount = AtomicLong(0)
    private val processedFramesCount = AtomicLong(0)
    private val droppedFramesCount = AtomicLong(0)
    private val replacedFramesCount = AtomicLong(0)

    // حساب الـ FPS خلال نافذة زمنية (كل 1 ثانية)
    private var lastFpsCalculationTime = SystemClock.elapsedRealtime()
    private var lastDeliveredCount = 0L
    private var lastProcessedCount = 0L
    private var currentDeliveredFps = 0.0
    private var currentProcessedFps = 0.0

    // قياسات الزمن
    private var totalFrameAgeMs = 0L
    private var frameAgeSamplesCount = 0L
    private var totalProcessingTimeMs = 0L
    private var processingSamplesCount = 0L
    private var maxProcessingTimeMs = 0L

    // حالة الانشغال لتطبيق Latest-Frame-Wins بدقة
    private val isProcessing = AtomicBoolean(false)

    fun updateRequestedFps(fps: Int) {
        requestedFps = fps
    }

    override fun analyze(image: ImageProxy) {
        val arrivalTimeMs = SystemClock.elapsedRealtime()
        deliveredFramesCount.incrementAndGet()

        // 1. حساب الـ FPS الدوري
        val now = arrivalTimeMs
        val elapsed = now - lastFpsCalculationTime
        if (elapsed >= 1000L) {
            val deliveredDelta = deliveredFramesCount.get() - lastDeliveredCount
            val processedDelta = processedFramesCount.get() - lastProcessedCount
            currentDeliveredFps = (deliveredDelta * 1000.0) / elapsed
            currentProcessedFps = (processedDelta * 1000.0) / elapsed

            lastFpsCalculationTime = now
            lastDeliveredCount = deliveredFramesCount.get()
            lastProcessedCount = processedFramesCount.get()
        }

        // 2. فحص عمر الفريم (Frame Age)
        // زمن التقاط الصورة بالمللي ثانية
        val captureTimestampMs = image.imageInfo.timestamp / 1_000_000L
        val frameAgeMs = if (captureTimestampMs > 0) {
            // فارق الوقت بين الالتقاط والاستلام
            (SystemClock.elapsedRealtime() - captureTimestampMs).coerceAtLeast(0)
        } else {
            0L
        }

        totalFrameAgeMs += frameAgeMs
        frameAgeSamplesCount++

        // 3. تخطي الفريم إذا كان قديماً جداً (Backlog prevention)
        if (frameAgeMs > MAX_STALE_FRAME_AGE_MS) {
            droppedFramesCount.incrementAndGet()
            image.close()
            return
        }

        // 4. تطبيق Latest-Frame-Wins: إذا كانت المعالجة السابقة جارية
        if (!isProcessing.compareAndSet(false, true)) {
            replacedFramesCount.incrementAndGet()
            image.close()
            return
        }

        // 5. تسليم الفريم للمعالجة مع الإغلاق الصارم داخل try/finally
        val processingStart = SystemClock.elapsedRealtime()
        try {
            onFrameReceived(image, captureTimestampMs)
            processedFramesCount.incrementAndGet()
        } catch (e: Exception) {
            Log.e(TAG, "Exception during frame analysis: ${e.message}", e)
        } finally {
            val processingDuration = SystemClock.elapsedRealtime() - processingStart
            totalProcessingTimeMs += processingDuration
            processingSamplesCount++
            if (processingDuration > maxProcessingTimeMs) {
                maxProcessingTimeMs = processingDuration
            }

            // إغلاق الفريم حتماً
            image.close()
            isProcessing.set(false)
        }
    }

    /**
     * استخراج تقرير المقاييس الفعلي
     */
    fun getMetrics(): CameraPerformanceMetrics {
        val avgAge = if (frameAgeSamplesCount > 0) totalFrameAgeMs.toDouble() / frameAgeSamplesCount else 0.0
        val avgProcessing = if (processingSamplesCount > 0) totalProcessingTimeMs.toDouble() / processingSamplesCount else 0.0

        return CameraPerformanceMetrics(
            requestedFps = requestedFps,
            cameraDeliveredFps = currentDeliveredFps,
            landmarkProcessedFps = currentProcessedFps,
            droppedCameraFrames = droppedFramesCount.get(),
            replacedPendingFrames = replacedFramesCount.get(),
            averageFrameAgeMs = avgAge,
            averageLandmarkProcessingMs = avgProcessing,
            maxLandmarkProcessingMs = maxProcessingTimeMs
        )
    }

    fun resetMetrics() {
        deliveredFramesCount.set(0)
        processedFramesCount.set(0)
        droppedFramesCount.set(0)
        replacedFramesCount.set(0)
        totalFrameAgeMs = 0L
        frameAgeSamplesCount = 0L
        totalProcessingTimeMs = 0L
        processingSamplesCount = 0L
        maxProcessingTimeMs = 0L
        currentDeliveredFps = 0.0
        currentProcessedFps = 0.0
        lastFpsCalculationTime = SystemClock.elapsedRealtime()
    }
}
