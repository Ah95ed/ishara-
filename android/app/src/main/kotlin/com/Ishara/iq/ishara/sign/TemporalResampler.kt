package com.Ishara.iq.ishara.sign

import com.Ishara.iq.ishara.vision.Keypoint2D
import com.Ishara.iq.ishara.vision.KeypointFrame86
import com.Ishara.iq.ishara.vision.KeypointMapper86

/**
 * نتيجة الاستيفاء الزمني مع الحفاظ على البيانات الوصفية الأصلية
 */
data class ResampledSequence(
    val originalFramesCount: Int,
    val originalDurationMs: Long,
    val originalFps: Double,
    val resampledFramesCount: Int = 128,
    // Tensor مسطح بالأبعاد [1, 128, 86, 2] جاهز تماماً لـ TFLite (طوله 1 * 128 * 86 * 2 = 22016)
    val modelInputArray: FloatArray
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as ResampledSequence
        return originalFramesCount == other.originalFramesCount &&
                originalDurationMs == other.originalDurationMs &&
                modelInputArray.contentEquals(other.modelInputArray)
    }

    override fun hashCode(): Int {
        var result = originalFramesCount
        result = 31 * result + originalDurationMs.hashCode()
        result = 31 * result + modelInputArray.contentHashCode()
        return result
    }
}

/**
 * محول ومستوفي الإشارات الزمني (TemporalResampler)
 * يستوفي مقاطع الإشارات الطبيعية (سواء كانت 20 أو 45 أو 80 فريم)
 * بدقة رياضية على المحور الزمني (t) لتوليد مصفوفة [1, 128, 86, 2] المطابقة لمدخل الموديل.
 */
object TemporalResampler {

    const val TARGET_FRAMES = 128
    const val KEYPOINTS_PER_FRAME = KeypointMapper86.TOTAL_KEYPOINTS // 86
    const val COORDS_PER_KEYPOINT = 2 // (x, y)
    const val VALUES_PER_FRAME = KEYPOINTS_PER_FRAME * COORDS_PER_KEYPOINT // 172
    const val TOTAL_TENSOR_SIZE = TARGET_FRAMES * VALUES_PER_FRAME // 22016

    /**
     * إعادة استيفاء قائمة الإطارات إلى 128 إطاراً بدقة
     */
    fun resample(segment: SignSegment): ResampledSequence {
        val frames = segment.frames
        val n = frames.size
        val output = FloatArray(TOTAL_TENSOR_SIZE)

        val durationMs = segment.durationMs
        val originalFps = if (durationMs > 0) (n * 1000.0) / durationMs else 30.0

        if (n == 0) {
            return ResampledSequence(
                originalFramesCount = 0,
                originalDurationMs = durationMs,
                originalFps = 0.0,
                modelInputArray = output
            )
        }

        if (n == 1) {
            // تكرار الإطار الوحيد عبر الـ 128 إطاراً
            val singleFlat = frames[0].toFlatFloatArray()
            for (t in 0 until TARGET_FRAMES) {
                System.arraycopy(singleFlat, 0, output, t * VALUES_PER_FRAME, VALUES_PER_FRAME)
            }
            return ResampledSequence(
                originalFramesCount = 1,
                originalDurationMs = durationMs,
                originalFps = originalFps,
                modelInputArray = output
            )
        }

        // تحويل جميع الإطارات إلى مصفوفات مسطحة مسبقاً لتسريع الحسابات
        val flatFrames = Array(n) { i -> frames[i].toFlatFloatArray() }

        // استيفاء خطي منتظم عبر المحور الزمني t in [0, 1]
        for (targetIdx in 0 until TARGET_FRAMES) {
            // الموضع النسبي على المحور الزمني الأصلي
            val relPos = (targetIdx.toFloat() / (TARGET_FRAMES - 1).toFloat()) * (n - 1).toFloat()
            val leftIdx = relPos.toInt().coerceIn(0, n - 2)
            val rightIdx = (leftIdx + 1).coerceIn(0, n - 1)
            val fraction = relPos - leftIdx

            val leftFrame = flatFrames[leftIdx]
            val rightFrame = flatFrames[rightIdx]
            val offset = targetIdx * VALUES_PER_FRAME

            for (k in 0 until VALUES_PER_FRAME) {
                val valL = leftFrame[k]
                val valR = rightFrame[k]
                output[offset + k] = valL + (valR - valL) * fraction
            }
        }

        return ResampledSequence(
            originalFramesCount = n,
            originalDurationMs = durationMs,
            originalFps = originalFps,
            modelInputArray = output
        )
    }
}
