package com.Ishara.iq.ishara.camera

import android.util.Range
import android.util.Size

/**
 * محدد استراتيجية الـ FPS ودقة الكاميرا (CameraFpsSelector)
 * الأولوية: 60 FPS إذا كانت الكاميرا تدعمه ومستقرة، وإلا 30 FPS.
 * الدقة: تفضيل 640x480 أو 1280x720 لضمان أعلى دقة زمنية بأقل تأخير.
 */
object CameraFpsSelector {

    /**
     * اختيار أفضل نطاق FPS مدعوم:
     * الأولوية لـ 60 FPS إن وجد، ثم 30 FPS.
     * تجنب النطاقات المخصصة للحركة البطيئة (Slow Motion > 60).
     */
    fun selectBestFpsRange(supportedRanges: List<Range<Int>>): Range<Int> {
        if (supportedRanges.isEmpty()) {
            return Range(30, 30)
        }

        // 1. البحث عن نطاق ثابت 60 فريم [60, 60]
        val exact60 = supportedRanges.find { it.lower == 60 && it.upper == 60 }
        if (exact60 != null) return exact60

        // 2. البحث عن نطاق ديناميكي يصل لـ 60 فريم (مثل [30, 60] أو [15, 60])
        val max60 = supportedRanges
            .filter { it.upper == 60 }
            .maxByOrNull { it.lower }
        if (max60 != null) return max60

        // 3. البحث عن نطاق ثابت 30 فريم [30, 30]
        val exact30 = supportedRanges.find { it.lower == 30 && it.upper == 30 }
        if (exact30 != null) return exact30

        // 4. البحث عن نطاق يصل لـ 30 فريم
        val max30 = supportedRanges
            .filter { it.upper in 24..30 }
            .maxByOrNull { it.upper }
        if (max30 != null) return max30

        // 5. في حال عدم وجود أي مما سبق، اختيار أعلى نطاق لا يتجاوز 60 فريم
        return supportedRanges
            .filter { it.upper <= 60 }
            .maxByOrNull { it.upper }
            ?: supportedRanges.first()
    }

    /**
     * اختيار الدقة المثلى لمعالجة المعالم (ImageAnalysis):
     * تفضيل 640x480 أولاً لدقتها وسرعتها، أو 720p (1280x720 / 960x720).
     */
    fun selectOptimalResolution(supportedSizes: List<Size>): Size {
        if (supportedSizes.isEmpty()) {
            return Size(640, 480)
        }

        // 1. فحص تواجد 640x480 بدقة
        val vga = supportedSizes.find {
            (it.width == 640 && it.height == 480) || (it.width == 480 && it.height == 640)
        }
        if (vga != null) return vga

        // 2. فحص 720p (1280x720)
        val hd = supportedSizes.find {
            (it.width == 1280 && it.height == 720) || (it.width == 720 && it.height == 1280)
        }
        if (hd != null) return hd

        // 3. اختيار أقرب دقة لـ 640x480 (حوالي 300,000 بكسل)
        val targetPixels = 640 * 480
        return supportedSizes.minByOrNull {
            val pixels = it.width * it.height
            kotlin.math.abs(pixels - targetPixels)
        } ?: supportedSizes.first()
    }
}
