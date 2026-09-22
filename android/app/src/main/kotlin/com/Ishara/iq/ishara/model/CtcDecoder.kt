package com.Ishara.iq.ishara.model

/**
 * نتيجة فك ترميز CTC (CtcDecodeResult)
 */
data class CtcDecodeResult(
    val rawArgmax: IntArray,
    val collapsedIds: IntArray,
    val decodedIds: IntArray
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as CtcDecodeResult
        return rawArgmax.contentEquals(other.rawArgmax) &&
                collapsedIds.contentEquals(other.collapsedIds) &&
                decodedIds.contentEquals(other.decodedIds)
    }

    override fun hashCode(): Int {
        var result = rawArgmax.contentHashCode()
        result = 31 * result + collapsedIds.contentHashCode()
        result = 31 * result + decodedIds.contentHashCode()
        return result
    }
}

/**
 * مفكك ترميز CTC الجشع (CtcDecoder)
 * يطبق خوارزمية Greedy CTC الصارمة:
 * 1. دمج التكرارات المتتالية المتجاورة (Collapse consecutive duplicates).
 * 2. إزالة المعرّف الفارغ (Remove Blank ID = 0).
 * 3. الحفاظ على التكرار الحقيقي المفصول بـ Blank (مثل: 5 5 0 5 5 -> 5 5).
 */
object CtcDecoder {

    const val BLANK_ID = 0

    /**
     * فك الترميز من مصفوفة الـ Argmax (بطول 29 خطوة زمنية)
     */
    fun decodeArgmax(rawArgmax: IntArray): CtcDecodeResult {
        if (rawArgmax.isEmpty()) {
            return CtcDecodeResult(intArrayOf(), intArrayOf(), intArrayOf())
        }

        // 1. دمج التكرارات المتتالية
        val collapsed = mutableListOf<Int>()
        var prev = -1
        for (id in rawArgmax) {
            if (id != prev) {
                collapsed.add(id)
                prev = id
            }
        }

        // 2. إزالة الـ Blank ID = 0
        val decoded = collapsed.filter { it != BLANK_ID }

        return CtcDecodeResult(
            rawArgmax = rawArgmax,
            collapsedIds = collapsed.toIntArray(),
            decodedIds = decoded.toIntArray()
        )
    }
}
