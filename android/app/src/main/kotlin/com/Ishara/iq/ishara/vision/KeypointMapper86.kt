package com.Ishara.iq.ishara.vision

/**
 * نقطة معلم ثنائية الأبعاد (2D Keypoint)
 */
data class Keypoint2D(
    val x: Float,
    val y: Float,
    val isValid: Boolean = true
) {
    companion object {
        val MISSING = Keypoint2D(0.0f, 0.0f, false)
    }
}

/**
 * إطار معالم الـ 86 نقطة (KeypointFrame86)
 * يحمل مصفوفة الـ 86 نقطة [86, 2] مع التوقيت وحالة المعالم
 */
data class KeypointFrame86(
    val keypoints: Array<Keypoint2D>, // length = 86
    val timestampMs: Long,
    val rightHandValid: Boolean,
    val leftHandValid: Boolean,
    val lipsValid: Boolean,
    val bodyValid: Boolean,
    val imputedMask: BooleanArray = BooleanArray(86) { false }
) {
    val validCount: Int get() = keypoints.count { it.isValid }
    val missingCount: Int get() = 86 - validCount

    /**
     * تحويل الإطار إلى مصفوفة أحادية مسطحة بطول 172 (86 * 2)
     */
    fun toFlatFloatArray(): FloatArray {
        val flat = FloatArray(86 * 2)
        for (i in 0 until 86) {
            val kp = keypoints[i]
            flat[i * 2] = kp.x
            flat[i * 2 + 1] = kp.y
        }
        return flat
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as KeypointFrame86
        return timestampMs == other.timestampMs && keypoints.contentEquals(other.keypoints)
    }

    override fun hashCode(): Int {
        var result = keypoints.contentHashCode()
        result = 31 * result + timestampMs.hashCode()
        return result
    }
}

/**
 * مخطط ومطابق نقاط الموديل الـ 86 المعتمد (KeypointMapper86)
 * تم تجميد الترتيب ومطابقته 100% مع datasetv2.py / PoseDatasetV2:
 * 0..20:   Right Hand (21 نقطة)
 * 21..41:  Left Hand  (21 نقطة)
 * 42..60:  Lips       (19 نقطة من Face Mesh)
 * 61..85:  Body/Head  (25 نقطة من Pose)
 */
object KeypointMapper86 {
    const val NUM_RIGHT_HAND = 21
    const val NUM_LEFT_HAND = 21
    const val NUM_LIPS = 19
    const val NUM_BODY = 25
    const val TOTAL_KEYPOINTS = 86

    const val RIGHT_HAND_OFFSET = 0
    const val LEFT_HAND_OFFSET = 21
    const val LIPS_OFFSET = 42
    const val BODY_OFFSET = 61

    // فهارس الشفاه الخارجية الـ 19 المستخرجة من MediaPipe Face Mesh
    val LIP_MESH_INDICES = intArrayOf(
        0, 17, 37, 39, 40, 61, 84, 91, 146, 181,
        185, 267, 269, 270, 291, 314, 321, 375, 405
    )

    // فهارس الرأس والجسم العلوي الـ 25 من MediaPipe Pose (0..24)
    val UPPER_BODY_INDICES = IntArray(25) { it }

    /**
     * بناء إطار نقاط الـ 86 الخام (Raw Keypoints) من مخرجات الكواشف
     */
    fun buildRawFrame(
        rightHandPoints: List<Keypoint2D>?,
        leftHandPoints: List<Keypoint2D>?,
        lipsPoints: List<Keypoint2D>?,
        bodyPoints: List<Keypoint2D>?,
        timestampMs: Long
    ): KeypointFrame86 {
        val points = Array(TOTAL_KEYPOINTS) { Keypoint2D.MISSING }

        val rhValid = !rightHandPoints.isNullOrEmpty()
        val lhValid = !leftHandPoints.isNullOrEmpty()
        val lipsValid = !lipsPoints.isNullOrEmpty()
        val bodyValid = !bodyPoints.isNullOrEmpty()

        // 1. Right Hand [0..20]
        if (rhValid && rightHandPoints != null) {
            val count = minOf(rightHandPoints.size, NUM_RIGHT_HAND)
            for (i in 0 until count) {
                points[RIGHT_HAND_OFFSET + i] = rightHandPoints[i]
            }
        }

        // 2. Left Hand [21..41]
        if (lhValid && leftHandPoints != null) {
            val count = minOf(leftHandPoints.size, NUM_LEFT_HAND)
            for (i in 0 until count) {
                points[LEFT_HAND_OFFSET + i] = leftHandPoints[i]
            }
        }

        // 3. Lips [42..60] (19 نقطة)
        if (lipsValid && lipsPoints != null) {
            val count = minOf(lipsPoints.size, NUM_LIPS)
            for (i in 0 until count) {
                points[LIPS_OFFSET + i] = lipsPoints[i]
            }
        }

        // 4. Body [61..85] (25 نقطة)
        if (bodyValid && bodyPoints != null) {
            val count = minOf(bodyPoints.size, NUM_BODY)
            for (i in 0 until count) {
                points[BODY_OFFSET + i] = bodyPoints[i]
            }
        }

        return KeypointFrame86(
            keypoints = points,
            timestampMs = timestampMs,
            rightHandValid = rhValid,
            leftHandValid = lhValid,
            lipsValid = lipsValid,
            bodyValid = bodyValid
        )
    }
}
