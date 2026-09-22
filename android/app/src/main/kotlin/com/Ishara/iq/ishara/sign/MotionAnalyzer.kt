package com.Ishara.iq.ishara.sign

import com.Ishara.iq.ishara.vision.KeypointFrame86
import com.Ishara.iq.ishara.vision.KeypointMapper86
import kotlin.math.hypot
import kotlin.math.max

/**
 * خصائص الحركة المحسوبة لكل إطار (MotionFrameFeatures)
 */
data class MotionFrameFeatures(
    val timestampMs: Long,
    val rightHandMotion: Float,
    val leftHandMotion: Float,
    val activeHandMotion: Float,
    val bodyMotion: Float,
    val baseline: Float,
    val startThreshold: Float,
    val endThreshold: Float
)

/**
 * محلل الحركة المنسوبة للجسم (MotionAnalyzer)
 * يحسب الحركة بالنسبة لنقطة منتصف الكتفين لمنع اعتبار اهتزاز الهاتف إشارة كاذبة.
 * يحدد خط الأساس التكيفي (Adaptive Baseline) والعتبات بهيستيريسيس (Hysteresis).
 */
class MotionAnalyzer(
    private val startMargin: Float = 0.012f,
    private val endMargin: Float = 0.005f,
    private val minMotionSensitivity: Float = 0.015f
) {
    companion object {
        // في مصفوفة الـ 86 نقطة:
        // Left Shoulder  = Body offset (61) + 11 = 72
        // Right Shoulder = Body offset (61) + 12 = 73
        // Right Wrist    = Right Hand offset (0) + 0 = 0
        // Left Wrist     = Left Hand offset (21) + 0 = 21
        const val LEFT_SHOULDER_INDEX = 72
        const val RIGHT_SHOULDER_INDEX = 73
        const val RIGHT_WRIST_INDEX = 0
        const val LEFT_WRIST_INDEX = 21
    }

    private var previousFrame: KeypointFrame86? = null
    private var prevRelRightWristX = 0.0f
    private var prevRelRightWristY = 0.0f
    private var prevRelLeftWristX = 0.0f
    private var prevRelLeftWristY = 0.0f
    private var prevBodyCenterX = 0.5f
    private var prevBodyCenterY = 0.5f

    // خط الأساس التكيفي (EMA Baseline)
    var motionBaseline: Float = 0.008f
        private set

    val startThreshold: Float get() = max(motionBaseline + startMargin, minMotionSensitivity)
    val endThreshold: Float get() = motionBaseline + endMargin

    /**
     * حساب الحركة لإطار جديد
     */
    fun computeMotion(frame: KeypointFrame86, isIdle: Boolean): MotionFrameFeatures {
        val kps = frame.keypoints

        // 1. تحديد مركز الكتفين ومقياس التحجيم
        val lShoulder = kps[LEFT_SHOULDER_INDEX]
        val rShoulder = kps[RIGHT_SHOULDER_INDEX]

        val bodyCenterX: Float
        val bodyCenterY: Float
        val shoulderWidth: Float

        if (lShoulder.isValid && rShoulder.isValid) {
            bodyCenterX = (lShoulder.x + rShoulder.x) * 0.5f
            bodyCenterY = (lShoulder.y + rShoulder.y) * 0.5f
            val sw = hypot(rShoulder.x - lShoulder.x, rShoulder.y - lShoulder.y)
            shoulderWidth = if (sw > 0.05f) sw else 0.20f
        } else {
            bodyCenterX = prevBodyCenterX
            bodyCenterY = prevBodyCenterY
            shoulderWidth = 0.20f
        }

        // 2. حركة الجسم العامة (Global Body Motion)
        val bodyMotion = hypot(bodyCenterX - prevBodyCenterX, bodyCenterY - prevBodyCenterY)
        prevBodyCenterX = bodyCenterX
        prevBodyCenterY = bodyCenterY

        // 3. الإحداثيات النسبية للمعصمين بالنسبة للجسم مقسومة على عرض الكتفين
        val rWrist = kps[RIGHT_WRIST_INDEX]
        val relRightX = if (rWrist.isValid) (rWrist.x - bodyCenterX) / shoulderWidth else prevRelRightWristX
        val relRightY = if (rWrist.isValid) (rWrist.y - bodyCenterY) / shoulderWidth else prevRelRightWristY

        val lWrist = kps[LEFT_WRIST_INDEX]
        val relLeftX = if (lWrist.isValid) (lWrist.x - bodyCenterX) / shoulderWidth else prevRelLeftWristX
        val relLeftY = if (lWrist.isValid) (lWrist.y - bodyCenterY) / shoulderWidth else prevRelLeftWristY

        // 4. حساب دلتا الحركة النسبية
        var rhMotion = 0.0f
        if (rWrist.isValid && previousFrame != null) {
            rhMotion = hypot(relRightX - prevRelRightWristX, relRightY - prevRelRightWristY)
        }

        var lhMotion = 0.0f
        if (lWrist.isValid && previousFrame != null) {
            lhMotion = hypot(relLeftX - prevRelLeftWristX, relLeftY - prevRelLeftWristY)
        }

        prevRelRightWristX = relRightX
        prevRelRightWristY = relRightY
        prevRelLeftWristX = relLeftX
        prevRelLeftWristY = relLeftY
        previousFrame = frame

        // 5. الحركة النشطة (دعم إشارة اليد الواحدة: اليد الأكثر حركة تمثل الإشارة)
        val activeMotion = max(rhMotion, lhMotion)

        // 6. تحديث خط الأساس التكيفي (EMA) أثناء السكون (IDLE) فقط
        if (isIdle && activeMotion > 0.0f) {
            val alpha = 0.05f
            motionBaseline = motionBaseline * (1.0f - alpha) + activeMotion * alpha
        }

        return MotionFrameFeatures(
            timestampMs = frame.timestampMs,
            rightHandMotion = rhMotion,
            leftHandMotion = lhMotion,
            activeHandMotion = activeMotion,
            bodyMotion = bodyMotion,
            baseline = motionBaseline,
            startThreshold = startThreshold,
            endThreshold = endThreshold
        )
    }

    fun reset() {
        previousFrame = null
        motionBaseline = 0.008f
        prevRelRightWristX = 0.0f
        prevRelRightWristY = 0.0f
        prevRelLeftWristX = 0.0f
        prevRelLeftWristY = 0.0f
        prevBodyCenterX = 0.5f
        prevBodyCenterY = 0.5f
    }
}
