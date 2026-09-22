package com.Ishara.iq.ishara.bridge

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.camera.view.PreviewView
import androidx.lifecycle.LifecycleOwner
import com.Ishara.iq.ishara.camera.IsharaCameraEngine
import com.Ishara.iq.ishara.model.IsharaModelRunner
import com.Ishara.iq.ishara.model.NativeInferenceResult
import com.Ishara.iq.ishara.sign.MotionFrameFeatures
import com.Ishara.iq.ishara.sign.SignSegment
import com.Ishara.iq.ishara.sign.SignSegmenter
import com.Ishara.iq.ishara.sign.SignState
import com.Ishara.iq.ishara.sign.TemporalResampler
import com.Ishara.iq.ishara.vision.FrameQualityMetrics
import com.Ishara.iq.ishara.vision.LandmarkEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * الجسر الموحد بين Native Android Vision Engine وواجهة Flutter (IsharaFlutterBridge)
 * مسؤول عن:
 * 1. معالجة أوامر Flutter (MethodChannel: com.ishara.native_vision/commands).
 * 2. بث أحداث الرؤية الخفيفة لـ Flutter (EventChannel: com.ishara.native_vision/events).
 * 3. تنسيق دورة العمل الكاملة: CameraX -> Landmarks -> Motion -> Segmentation -> Resampling -> TFLite -> CTC.
 * 4. توليد تقرير التشخيص الكامل (Section 35) للمراجعة ونسخه للحافظة.
 */
class IsharaFlutterBridge(
    private val activity: Activity,
    private val lifecycleOwner: LifecycleOwner,
    binaryMessenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "IsharaFlutterBridge"
        const val COMMAND_CHANNEL = "com.ishara.native_vision/commands"
        const val EVENT_CHANNEL = "com.ishara.native_vision/events"
        const val PREVIEW_VIEW_TYPE = "com.ishara.native_vision/camera_preview"
    }

    private val methodChannel = MethodChannel(binaryMessenger, COMMAND_CHANNEL)
    private val eventChannel = EventChannel(binaryMessenger, EVENT_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var eventSink: EventChannel.EventSink? = null
    private var attachedPreviewView: PreviewView? = null

    // ── المكونات الأساسية للـ Pipeline ──
    private val landmarkEngine = LandmarkEngine(activity)
    private val signSegmenter = SignSegmenter()
    private val modelRunner = IsharaModelRunner(activity)
    private lateinit var cameraEngine: IsharaCameraEngine

    // لقطات تشخيصية لتقرير النسخ (Section 35)
    private var latestQualityMetrics: FrameQualityMetrics? = null
    private var latestMotionFeatures: MotionFrameFeatures? = null
    private var latestSegment: SignSegment? = null
    private var latestInferenceResult: NativeInferenceResult? = null
    private var lastError: String = "NONE"

        init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)

        cameraEngine = IsharaCameraEngine(
            context = activity,
            lifecycleOwner = lifecycleOwner,
            onFrame = { imageProxy, timestampMs ->
                landmarkEngine.processImageProxy(
                    imageProxy = imageProxy,
                    timestampMs = timestampMs,
                    isFrontCamera = cameraEngine.isFrontCamera,
                    onResult = { landmarkResult ->
                        onLandmarkResult(landmarkResult.rawFrame, landmarkResult.qualityMetrics)
                    }
                )
            }
        )
    }

    fun onPreviewViewCreated(previewView: PreviewView) {
        this.attachedPreviewView = previewView
        cameraEngine.attachPreviewView(previewView)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initializeNativeVision" -> {
                modelRunner.initialize { modelReady ->
                    val capabilities = cameraEngine.probe.probeAllCameras().mapValues { it.value.toMap() }
                    sendToFlutter(
                        mapOf(
                            "event" to "INITIALIZED",
                            "modelReady" to modelReady,
                            "capabilities" to capabilities
                        )
                    )
                    result.success(modelReady)
                }
            }

            "startVision" -> {
                val useFront = call.argument<Boolean>("useFrontCamera") ?: true
                cameraEngine.startCamera(attachedPreviewView, useFront) { profile ->
                    sendToFlutter(
                        mapOf(
                            "event" to "CAMERA_STARTED",
                            "profile" to profile?.toMap()
                        )
                    )
                    result.success(true)
                }
            }

            "stopVision" -> {
                cameraEngine.stopCamera()
                signSegmenter.reset()
                sendToFlutter(mapOf("event" to "CAMERA_STOPPED"))
                result.success(true)
            }

            "switchCamera" -> {
                cameraEngine.switchCamera { profile ->
                    signSegmenter.reset()
                    landmarkEngine.reset()
                    sendToFlutter(
                        mapOf(
                            "event" to "CAMERA_SWITCHED",
                            "profile" to profile?.toMap()
                        )
                    )
                    result.success(true)
                }
            }

            "getCameraCapabilities" -> {
                val capabilities = cameraEngine.probe.probeAllCameras().mapValues { it.value.toMap() }
                result.success(capabilities)
            }

            "getPerformanceMetrics" -> {
                result.success(cameraEngine.analyzer.getMetrics().toMap())
            }

            "getDiagnosticReport" -> {
                result.success(buildSection35DiagnosticReport())
            }

            "resetSession" -> {
                signSegmenter.reset()
                landmarkEngine.reset()
                sendToFlutter(mapOf("event" to "STATE_CHANGED", "state" to "IDLE"))
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
    }

    /**
     * معالجة نتائج المعالم واستخراج الحركة وتقطيع الإشارة
     */
    private fun onLandmarkResult(rawFrame: com.Ishara.iq.ishara.vision.KeypointFrame86, quality: FrameQualityMetrics) {
        latestQualityMetrics = quality
        val prevState = signSegmenter.state

        val motion = signSegmenter.processFrame(rawFrame) { completedSegment ->
            // عند اكتمال مقطع إشارة: تشغيل الاستيفاء الزمني والاستنتاج
            onSignSegmentCompleted(completedSegment)
        }
        latestMotionFeatures = motion

        // إرسال تحديث الحالة إذا تغيرت
        if (signSegmenter.state != prevState) {
            sendToFlutter(
                mapOf(
                    "event" to "STATE_CHANGED",
                    "state" to signSegmenter.state.name,
                    "previousState" to prevState.name
                )
            )
        }
    }

    /**
     * تشغيل الاستيفاء والاستنتاج لمقطع الإشارة المكتمل
     */
    private fun onSignSegmentCompleted(segment: SignSegment) {
        latestSegment = segment

        sendToFlutter(
            mapOf(
                "event" to "STATE_CHANGED",
                "state" to "PROCESSING",
                "originalFrames" to segment.frameCount,
                "durationMs" to segment.durationMs
            )
        )

        // 1. الاستيفاء الزمني الذكي N -> 128
        val resampled = TemporalResampler.resample(segment)

        // 2. تشغيل استنتاج TFLite في خيط منفصل
        modelRunner.runInference(resampled.modelInputArray) { inferenceResult ->
            latestInferenceResult = inferenceResult
            signSegmenter.onProcessingFinished()

            if (inferenceResult.isSuccess) {
                sendToFlutter(
                    mapOf(
                        "event" to "RESULT",
                        "state" to "RESULT",
                        "glosses" to inferenceResult.glosses,
                        "decodedIds" to inferenceResult.decodedIds.toList(),
                        "rawArgmax" to inferenceResult.rawArgmax.toList(),
                        "inferenceMs" to inferenceResult.inferenceTimeMs,
                        "durationMs" to segment.durationMs,
                        "originalFrames" to segment.frameCount,
                        "displayResult" to if (inferenceResult.glosses.isNotEmpty()) {
                            inferenceResult.glosses.joinToString(" - ")
                        } else {
                            "لم يتم التعرف على إشارة واضحة"
                        }
                    )
                )
            } else {
                lastError = inferenceResult.errorMessage ?: "Unknown inference error"
                sendToFlutter(
                    mapOf(
                        "event" to "FAILED",
                        "state" to "FAILED",
                        "errorMessage" to lastError
                    )
                )
            }
        }
    }

    /**
     * إرسال بيانات الحدث الخفيفة إلى Flutter عبر الـ EventChannel في الـ Main Thread
     */
    private fun sendToFlutter(data: Map<String, Any?>) {
        mainHandler.post {
            try {
                eventSink?.success(data)
            } catch (e: Exception) {
                Log.e(TAG, "Error sending event to Flutter: ${e.message}")
            }
        }
    }

    /**
     * توليد التقرير التشخيصي النصي المعتمد وفق البند 35
     */
    fun buildSection35DiagnosticReport(): String {
        val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)
        val nowStr = dateFormat.format(Date())

        val profile = cameraEngine.currentProfile
        val metrics = cameraEngine.analyzer.getMetrics()
        val quality = latestQualityMetrics
        val motion = latestMotionFeatures
        val seg = latestSegment
        val inf = latestInferenceResult

        return """
================================
ISHARA NATIVE VISION REPORT
================================

Captured At:
$nowStr

Camera:
Lens: ${if (cameraEngine.isFrontCamera) "FRONT" else "BACK"}
Camera ID: ${profile?.cameraId ?: "0"}
Requested FPS: ${metrics.requestedFps}
Supported FPS: ${profile?.supportedFpsRanges ?: "[]"}
Actual Camera FPS: ${String.format(Locale.US, "%.2f", metrics.cameraDeliveredFps)}
Resolution: ${profile?.selectedResolution ?: "N/A"}

Native pipeline:
Landmark FPS: ${String.format(Locale.US, "%.2f", metrics.landmarkProcessedFps)}
Dropped frames: ${metrics.droppedCameraFrames}
Replaced pending frames: ${metrics.replacedPendingFrames}
Average frame age: ${String.format(Locale.US, "%.2f", metrics.averageFrameAgeMs)} ms
Average processing: ${String.format(Locale.US, "%.2f", metrics.averageLandmarkProcessingMs)} ms
Max processing: ${metrics.maxLandmarkProcessingMs} ms

Sign:
Start detected: ${if (seg != null) "YES" else "NO"}
End detected: ${if (seg != null) "YES" else "NO"}
Start timestamp: ${seg?.startTimestampMs ?: 0}
End timestamp: ${seg?.endTimestampMs ?: 0}
Duration: ${seg?.durationMs ?: 0} ms
Original frames: ${seg?.frameCount ?: 0}
Pre-roll: 10 frames (~300ms)
Post-roll: ~6 frames (~200ms)
End reason: ${seg?.endReason ?: "N/A"}

Motion:
Baseline: ${String.format(Locale.US, "%.4f", motion?.baseline ?: 0.008f)}
Start threshold: ${String.format(Locale.US, "%.4f", motion?.startThreshold ?: 0.025f)}
End threshold: ${String.format(Locale.US, "%.4f", motion?.endThreshold ?: 0.015f)}
Peak motion: ${String.format(Locale.US, "%.4f", motion?.activeHandMotion ?: 0.0f)}

Coverage:
RH: ${String.format(Locale.US, "%.2f", quality?.rhCoveragePct ?: 0.0)} %
LH: ${String.format(Locale.US, "%.2f", quality?.lhCoveragePct ?: 0.0)} %
Lips: ${String.format(Locale.US, "%.2f", quality?.lipsCoveragePct ?: 0.0)} %
Body: ${String.format(Locale.US, "%.2f", quality?.bodyCoveragePct ?: 0.0)} %
Imputed: ${String.format(Locale.US, "%.2f", quality?.imputedPct ?: 0.0)} %

Resampling:
Original shape: [1, ${seg?.frameCount ?: 0}, 86, 2]
Final shape: [1, 128, 86, 2]

Model:
Load state: ${if (modelRunner.isModelLoaded) "LOADED" else "FAILED"}
Inference: ${if (inf?.isSuccess == true) "PASS" else "FAIL"}
Inference ms: ${inf?.inferenceTimeMs ?: 0} ms
Output shape: [1, 29, 684]

CTC:
Raw IDs: ${inf?.rawArgmax?.toList() ?: "[]"}
Decoded IDs: ${inf?.decodedIds?.toList() ?: "[]"}
Glosses: ${inf?.glosses ?: "[]"}

Errors:
$lastError
================================
""".trimIndent()
    }

    fun dispose() {
        cameraEngine.dispose()
        landmarkEngine.dispose()
        modelRunner.dispose()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }
}
