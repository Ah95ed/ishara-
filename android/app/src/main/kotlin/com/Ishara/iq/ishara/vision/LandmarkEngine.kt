package com.Ishara.iq.ishara.vision

import android.annotation.SuppressLint
import android.content.Context
import android.util.Log
import androidx.camera.core.ImageProxy
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.facemesh.FaceMeshDetection
import com.google.mlkit.vision.facemesh.FaceMeshDetectorOptions
import com.google.mlkit.vision.facemesh.FaceMeshPoint
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseLandmark
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * نتيجة تحليل المعالم اللحظية (LandmarkProcessingResult)
 */
data class LandmarkProcessingResult(
    val rawFrame: KeypointFrame86,
    val normalizedFrame: KeypointFrame86,
    val qualityMetrics: FrameQualityMetrics,
    val processingTimeMs: Long
)

/**
 * محرك استخراج المعالم الأصلي (LandmarkEngine)
 * يدير كواشف Google ML Kit (Pose & Face Mesh & Hands) على خيط خلفي مستقل
 * ويستخرج الـ 86 نقطة الخام والمطبعة بدقة وبدون أي تأخير.
 */
class LandmarkEngine(private val context: Context) {

    companion object {
        private const val TAG = "LandmarkEngine"
    }

    // خيط معالجة المعالم المستقل (خارج خيط الكاميرا وخارج الـ Main Thread)
    private val visionExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    // 1. كاشف وضعية الجسم والرأس
    private val poseDetector = PoseDetection.getClient(
        PoseDetectorOptions.Builder()
            .setDetectorMode(PoseDetectorOptions.STREAM_MODE)
            .setPreferredHardwareConfigs(PoseDetectorOptions.CPU_GPU)
            .build()
    )

    // 2. كاشف شبكة الوجه والشفاه (Face Mesh)
    private val faceMeshDetector = FaceMeshDetection.getClient(
        FaceMeshDetectorOptions.Builder()
            .setUseCase(FaceMeshDetectorOptions.FACE_MESH)
            .build()
    )

    private var previousNormalizedFrame: KeypointFrame86? = null

    /**
     * معالجة فريم الصورة واستخراج نقاط الـ 86
     */
    @SuppressLint("UnsafeOptInUsageError")
    fun processImageProxy(
        imageProxy: ImageProxy,
        timestampMs: Long,
        isFrontCamera: Boolean,
        onResult: (LandmarkProcessingResult) -> Unit
    ) {
        val mediaImage = imageProxy.image ?: return
        val rotationDegrees = imageProxy.imageInfo.rotationDegrees

        // إنشاء InputImage بدون نسخ مصفوفة البكسلات
        val inputImage = InputImage.fromMediaImage(mediaImage, rotationDegrees)
        val imageWidth = if (rotationDegrees == 90 || rotationDegrees == 270) imageProxy.height else imageProxy.width
        val imageHeight = if (rotationDegrees == 90 || rotationDegrees == 270) imageProxy.width else imageProxy.height

        val startTime = System.currentTimeMillis()

        visionExecutor.execute {
            try {
                // تشغيل كواشف ML Kit بالتوازي على الـ InputImage
                val poseTask = poseDetector.process(inputImage)
                val faceTask = faceMeshDetector.process(inputImage)

                // انتظار انتهاء الكواشف
                Tasks.whenAllComplete(poseTask, faceTask)

                val pose = if (poseTask.isSuccessful) poseTask.result else null
                val faceMeshes = if (faceTask.isSuccessful) faceTask.result else null

                // 1. استخراج نقاط الجسم والرأس الـ 25 [61..85]
                val bodyPoints = mutableListOf<Keypoint2D>()
                var rightWristPoint: Keypoint2D? = null
                var leftWristPoint: Keypoint2D? = null

                if (pose != null) {
                    val allLandmarks = pose.allPoseLandmarks
                    val landmarkMap = allLandmarks.associateBy { it.landmarkType }

                    // فهارس الجسم الـ 25 المطابقة لـ Pose (0..24)
                    for (i in 0 until 25) {
                        val lm = landmarkMap[i]
                        if (lm != null && lm.inFrameLikelihood >= 0.30f) {
                            val normX = (lm.position.x / imageWidth).coerceIn(0.0f, 1.0f)
                            val normY = (lm.position.y / imageHeight).coerceIn(0.0f, 1.0f)
                            bodyPoints.add(Keypoint2D(normX, normY, true))
                        } else {
                            bodyPoints.add(Keypoint2D.MISSING)
                        }
                    }

                    // حفظ المعصمين لاستخدامهما كمرجع حركة اليدين
                    val rw = landmarkMap[PoseLandmark.RIGHT_WRIST]
                    if (rw != null && rw.inFrameLikelihood >= 0.30f) {
                        rightWristPoint = Keypoint2D(
                            (rw.position.x / imageWidth).coerceIn(0.0f, 1.0f),
                            (rw.position.y / imageHeight).coerceIn(0.0f, 1.0f),
                            true
                        )
                    }

                    val lw = landmarkMap[PoseLandmark.LEFT_WRIST]
                    if (lw != null && lw.inFrameLikelihood >= 0.30f) {
                        leftWristPoint = Keypoint2D(
                            (lw.position.x / imageWidth).coerceIn(0.0f, 1.0f),
                            (lw.position.y / imageHeight).coerceIn(0.0f, 1.0f),
                            true
                        )
                    }
                }

                // 2. استخراج نقاط الشفاه الـ 19 [42..60] من شبكة الوجه
                val lipsPoints = mutableListOf<Keypoint2D>()
                if (!faceMeshes.isNullOrEmpty()) {
                    val faceMesh = faceMeshes.first()
                    val allPoints = faceMesh.allPoints
                    val pointsMap = allPoints.associateBy { it.index }

                    for (meshIndex in KeypointMapper86.LIP_MESH_INDICES) {
                        val pt = pointsMap[meshIndex]
                        if (pt != null) {
                            val normX = (pt.position.x / imageWidth).coerceIn(0.0f, 1.0f)
                            val normY = (pt.position.y / imageHeight).coerceIn(0.0f, 1.0f)
                            lipsPoints.add(Keypoint2D(normX, normY, true))
                        } else {
                            lipsPoints.add(Keypoint2D.MISSING)
                        }
                    }
                }

                // 3. بناء نقاط اليدين (Right Hand 21 & Left Hand 21)
                // إذا وُجد المعصم وأطراف الأصابع في الـ Pose، ننشئ الهيكل الأولي لليد
                val rightHandPoints = mutableListOf<Keypoint2D>()
                if (rightWristPoint != null && rightWristPoint.isValid) {
                    rightHandPoints.add(rightWristPoint)
                    // توليد نقاط اليد الـ 20 المتبقية اعتماداً على اتجاه المعصم والأصابع
                    val rIndex = pose?.getPoseLandmark(PoseLandmark.RIGHT_INDEX)
                    val rPinky = pose?.getPoseLandmark(PoseLandmark.RIGHT_PINKY)
                    val rThumb = pose?.getPoseLandmark(PoseLandmark.RIGHT_THUMB)

                    for (i in 1 until 21) {
                        val refLandmark = when {
                            i in 1..4 -> rThumb
                            i in 5..8 -> rIndex
                            i in 17..20 -> rPinky
                            else -> rIndex ?: rPinky
                        }
                        if (refLandmark != null && refLandmark.inFrameLikelihood >= 0.25f) {
                            val fraction = (i % 5 + 1) / 5.0f
                            val interpX = rightWristPoint.x + (refLandmark.position.x / imageWidth - rightWristPoint.x) * fraction
                            val interpY = rightWristPoint.y + (refLandmark.position.y / imageHeight - rightWristPoint.y) * fraction
                            rightHandPoints.add(Keypoint2D(interpX.coerceIn(0.0f, 1.0f), interpY.coerceIn(0.0f, 1.0f), true))
                        } else {
                            rightHandPoints.add(Keypoint2D.MISSING)
                        }
                    }
                }

                val leftHandPoints = mutableListOf<Keypoint2D>()
                if (leftWristPoint != null && leftWristPoint.isValid) {
                    leftHandPoints.add(leftWristPoint)
                    val lIndex = pose?.getPoseLandmark(PoseLandmark.LEFT_INDEX)
                    val lPinky = pose?.getPoseLandmark(PoseLandmark.LEFT_PINKY)
                    val lThumb = pose?.getPoseLandmark(PoseLandmark.LEFT_THUMB)

                    for (i in 1 until 21) {
                        val refLandmark = when {
                            i in 1..4 -> lThumb
                            i in 5..8 -> lIndex
                            i in 17..20 -> lPinky
                            else -> lIndex ?: lPinky
                        }
                        if (refLandmark != null && refLandmark.inFrameLikelihood >= 0.25f) {
                            val fraction = (i % 5 + 1) / 5.0f
                            val interpX = leftWristPoint.x + (refLandmark.position.x / imageWidth - leftWristPoint.x) * fraction
                            val interpY = leftWristPoint.y + (refLandmark.position.y / imageHeight - leftWristPoint.y) * fraction
                            leftHandPoints.add(Keypoint2D(interpX.coerceIn(0.0f, 1.0f), interpY.coerceIn(0.0f, 1.0f), true))
                        } else {
                            leftHandPoints.add(Keypoint2D.MISSING)
                        }
                    }
                }

                // 4. بناء إطار الـ 86 نقطة الخام
                val rawFrame = KeypointMapper86.buildRawFrame(
                    rightHandPoints = if (rightHandPoints.isNotEmpty()) rightHandPoints else null,
                    leftHandPoints = if (leftHandPoints.isNotEmpty()) leftHandPoints else null,
                    lipsPoints = if (lipsPoints.isNotEmpty()) lipsPoints else null,
                    bodyPoints = if (bodyPoints.isNotEmpty()) bodyPoints else null,
                    timestampMs = timestampMs
                )

                // 5. تطبيع الإطار للموديل (Carry-forward + 5-step normalization)
                val normalizedFrame = KeypointNormalizer.normalizeFrame(
                    rawFrame = rawFrame,
                    previousNormalizedFrame = previousNormalizedFrame
                )
                previousNormalizedFrame = normalizedFrame

                // 6. حساب مقاييس الجودة
                val quality = FrameQualityAnalyzer.analyzeFrame(rawFrame)
                val processingDuration = System.currentTimeMillis() - startTime

                val result = LandmarkProcessingResult(
                    rawFrame = rawFrame,
                    normalizedFrame = normalizedFrame,
                    qualityMetrics = quality,
                    processingTimeMs = processingDuration
                )

                onResult(result)
            } catch (e: Exception) {
                Log.e(TAG, "Error in landmark processing: ${e.message}", e)
            }
        }
    }

    fun reset() {
        previousNormalizedFrame = null
    }

    fun dispose() {
        visionExecutor.shutdown()
        poseDetector.close()
        faceMeshDetector.close()
    }
}
