package com.Ishara.iq.ishara.vision

import kotlin.math.abs
import kotlin.math.max

/**
 * معالج ومطبع النقاط الـ 86 الرياضي (KeypointNormalizer)
 * مطابق حرفياً لكود التدريب الأصلي datasetv2.py / PoseDatasetV2
 * يطبّق نفس الخطوات الخمس على المجموعات الأربع:
 * 1. Right Hand (21)
 * 2. Left Hand (21)
 * 3. Lips (19)
 * 4. Body (25)
 */
object KeypointNormalizer {

    /**
     * تطبيع مجموعة فرعية من النقاط [N, 2] حسب datasetv2.py
     */
    fun normalizeSubset(subset: Array<FloatArray>): Array<FloatArray> {
        val n = subset.size
        if (n == 0) return emptyArray()

        // 1. التحقق هل جميع النقاط أصفار
        var sum = 0.0f
        for (i in 0 until n) {
            sum += abs(subset[i][0]) + abs(subset[i][1])
        }
        if (sum < 1e-6f) {
            return Array(n) { floatArrayOf(0.0f, 0.0f) }
        }

        // إنشاء نسخة للعمليات الحسابية
        val result = Array(n) { i -> floatArrayOf(subset[i][0], subset[i][1]) }

        // 1. طرح أول نقطة pose[0]
        val originX = result[0][0]
        val originY = result[0][1]
        for (i in 0 until n) {
            result[i][0] -= originX
            result[i][1] -= originY
        }

        // 2. طرح أقل قيمة في كل محور لجعل البداية من الصفر
        var minX = result[0][0]
        var minY = result[0][1]
        for (i in 1 until n) {
            if (result[i][0] < minX) minX = result[i][0]
            if (result[i][1] < minY) minY = result[i][1]
        }
        for (i in 0 until n) {
            result[i][0] -= minX
            result[i][1] -= minY
        }

        // 3. التحجيم في صندوق 1x1: max_coord = max(maxX, maxY); pose /= max_coord
        var maxX = result[0][0]
        var maxY = result[0][1]
        for (i in 1 until n) {
            if (result[i][0] > maxX) maxX = result[i][0]
            if (result[i][1] > maxY) maxY = result[i][1]
        }
        val maxCoord = max(maxX, maxY)
        if (maxCoord > 1e-7f) {
            for (i in 0 until n) {
                result[i][0] /= maxCoord
                result[i][1] /= maxCoord
            }
        }

        // 4. طرح المتوسط العام لجميع العناصر: mean = total / (2 * n)
        var totalVal = 0.0f
        for (i in 0 until n) {
            totalVal += result[i][0] + result[i][1]
        }
        val meanVal = totalVal / (2.0f * n)
        for (i in 0 until n) {
            result[i][0] -= meanVal
            result[i][1] -= meanVal
        }

        // 5. القسمة على القيمة المطلقة العظمى والضرب في 0.5: pose = (pose / maxAbs) * 0.5
        var maxAbs = 0.0f
        for (i in 0 until n) {
            val ax = abs(result[i][0])
            val ay = abs(result[i][1])
            if (ax > maxAbs) maxAbs = ax
            if (ay > maxAbs) maxAbs = ay
        }
        if (maxAbs > 1e-7f) {
            for (i in 0 until n) {
                result[i][0] = (result[i][0] / maxAbs) * 0.5f
                result[i][1] = (result[i][1] / maxAbs) * 0.5f
            }
        }

        return result
    }

    /**
     * تطبيع إطار كامل من 86 نقطة مع تطبيق استراتيجية Carry-forward للنقاط المفقودة
     */
    fun normalizeFrame(
        rawFrame: KeypointFrame86,
        previousNormalizedFrame: KeypointFrame86? = null
    ): KeypointFrame86 {
        val rawPoints = rawFrame.keypoints
        val normalizedPoints = Array(KeypointMapper86.TOTAL_KEYPOINTS) { Keypoint2D.MISSING }
        val imputedMask = BooleanArray(KeypointMapper86.TOTAL_KEYPOINTS) { false }

        fun extractAndNormalizeSubset(
            offset: Int,
            count: Int
        ) {
            val sub = Array(count) { i ->
                val kp = rawPoints[offset + i]
                if (kp.isValid) {
                    floatArrayOf(kp.x, kp.y)
                } else {
                    // Carry-forward من الإطار السابق إذا وجد، وإلا أصفار
                    val prevKp = previousNormalizedFrame?.keypoints?.get(offset + i)
                    if (prevKp != null && prevKp.isValid) {
                        imputedMask[offset + i] = true
                        floatArrayOf(prevKp.x, prevKp.y)
                    } else {
                        floatArrayOf(0.0f, 0.0f)
                    }
                }
            }

            val normed = normalizeSubset(sub)
            for (i in 0 until count) {
                val isRawValid = rawPoints[offset + i].isValid
                val isImputed = imputedMask[offset + i]
                val isValid = isRawValid || isImputed
                normalizedPoints[offset + i] = Keypoint2D(
                    x = normed[i][0],
                    y = normed[i][1],
                    isValid = isValid
                )
            }
        }

        // 1. Right Hand [0..20]
        extractAndNormalizeSubset(KeypointMapper86.RIGHT_HAND_OFFSET, KeypointMapper86.NUM_RIGHT_HAND)

        // 2. Left Hand [21..41]
        extractAndNormalizeSubset(KeypointMapper86.LEFT_HAND_OFFSET, KeypointMapper86.NUM_LEFT_HAND)

        // 3. Lips [42..60]
        extractAndNormalizeSubset(KeypointMapper86.LIPS_OFFSET, KeypointMapper86.NUM_LIPS)

        // 4. Body [61..85]
        extractAndNormalizeSubset(KeypointMapper86.BODY_OFFSET, KeypointMapper86.NUM_BODY)

        return KeypointFrame86(
            keypoints = normalizedPoints,
            timestampMs = rawFrame.timestampMs,
            rightHandValid = rawFrame.rightHandValid,
            leftHandValid = rawFrame.leftHandValid,
            lipsValid = rawFrame.lipsValid,
            bodyValid = rawFrame.bodyValid,
            imputedMask = imputedMask
        )
    }
}
