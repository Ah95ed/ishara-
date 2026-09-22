package com.Ishara.iq.ishara.vision

/**
 * مقاييس جودة وتغطية الإطار (FrameQualityMetrics)
 */
data class FrameQualityMetrics(
    val totalRawCoveragePct: Double,
    val rhCoveragePct: Double,
    val lhCoveragePct: Double,
    val lipsCoveragePct: Double,
    val bodyCoveragePct: Double,
    val imputedPct: Double
) {
    fun toMap(): Map<String, Any> {
        return mapOf(
            "totalRawCoveragePct" to totalRawCoveragePct,
            "rhCoveragePct" to rhCoveragePct,
            "lhCoveragePct" to lhCoveragePct,
            "lipsCoveragePct" to lipsCoveragePct,
            "bodyCoveragePct" to bodyCoveragePct,
            "imputedPct" to imputedPct
        )
    }
}

/**
 * محلل جودة الإطارات وتغطية المعالم (FrameQualityAnalyzer)
 */
object FrameQualityAnalyzer {

    fun analyzeFrame(frame: KeypointFrame86): FrameQualityMetrics {
        val kps = frame.keypoints

        // Right Hand [0..20]
        var rhCount = 0
        for (i in 0 until KeypointMapper86.NUM_RIGHT_HAND) {
            if (kps[KeypointMapper86.RIGHT_HAND_OFFSET + i].isValid && !frame.imputedMask[KeypointMapper86.RIGHT_HAND_OFFSET + i]) {
                rhCount++
            }
        }
        val rhPct = (rhCount.toDouble() / KeypointMapper86.NUM_RIGHT_HAND) * 100.0

        // Left Hand [21..41]
        var lhCount = 0
        for (i in 0 until KeypointMapper86.NUM_LEFT_HAND) {
            if (kps[KeypointMapper86.LEFT_HAND_OFFSET + i].isValid && !frame.imputedMask[KeypointMapper86.LEFT_HAND_OFFSET + i]) {
                lhCount++
            }
        }
        val lhPct = (lhCount.toDouble() / KeypointMapper86.NUM_LEFT_HAND) * 100.0

        // Lips [42..60]
        var lipsCount = 0
        for (i in 0 until KeypointMapper86.NUM_LIPS) {
            if (kps[KeypointMapper86.LIPS_OFFSET + i].isValid && !frame.imputedMask[KeypointMapper86.LIPS_OFFSET + i]) {
                lipsCount++
            }
        }
        val lipsPct = (lipsCount.toDouble() / KeypointMapper86.NUM_LIPS) * 100.0

        // Body [61..85]
        var bodyCount = 0
        for (i in 0 until KeypointMapper86.NUM_BODY) {
            if (kps[KeypointMapper86.BODY_OFFSET + i].isValid && !frame.imputedMask[KeypointMapper86.BODY_OFFSET + i]) {
                bodyCount++
            }
        }
        val bodyPct = (bodyCount.toDouble() / KeypointMapper86.NUM_BODY) * 100.0

        val totalRawValid = rhCount + lhCount + lipsCount + bodyCount
        val totalRawCoveragePct = (totalRawValid.toDouble() / KeypointMapper86.TOTAL_KEYPOINTS) * 100.0

        val imputedCount = frame.imputedMask.count { it }
        val imputedPct = (imputedCount.toDouble() / KeypointMapper86.TOTAL_KEYPOINTS) * 100.0

        return FrameQualityMetrics(
            totalRawCoveragePct = totalRawCoveragePct,
            rhCoveragePct = rhPct,
            lhCoveragePct = lhPct,
            lipsCoveragePct = lipsPct,
            bodyCoveragePct = bodyPct,
            imputedPct = imputedPct
        )
    }
}
