package com.Ishara.iq.ishara.sign

import com.Ishara.iq.ishara.vision.KeypointFrame86

/**
 * حالات الإشارة الزمنية (SignState)
 */
enum class SignState {
    IDLE,
    STARTING,
    SIGNING,
    ENDING,
    PROCESSING
}

/**
 * المقطع الحركي المكتمل للإشارة (SignSegment)
 */
data class SignSegment(
    val frames: List<KeypointFrame86>,
    val durationMs: Long,
    val frameCount: Int,
    val startTimestampMs: Long,
    val endTimestampMs: Long,
    val endReason: String
)

/**
 * مقطع الإشارات الزمني (SignSegmenter)
 * يدير آلة الحالات الخماسية ومخازن Pre-Roll و Post-Roll
 * ويفصل الإشارة تلقائياً وبسرعتها الطبيعية دون إجبار المستخدم على التباطؤ.
 */
class SignSegmenter(
    val motionAnalyzer: MotionAnalyzer = MotionAnalyzer(),
    private val candidateDurationMs: Long = 140L, // 100-180ms لتأكيد البداية
    private val quietDurationMs: Long = 350L,     // 250-450ms لتأكيد الهدوء والنهاية
    private val minSignDurationMs: Long = 250L,    // الحد الأدنى لطول الإشارة
    private val maxSignDurationMs: Long = 12000L,  // سقف أمان أقصى 12 ثانية
    private val preRollMaxFrames: Int = 10         // مخزن ما قبل البداية (~300ms)
) {
    var state: SignState = SignState.IDLE
        private set

    private val preRollBuffer = ArrayDeque<KeypointFrame86>(preRollMaxFrames)
    private val activeSegmentFrames = mutableListOf<KeypointFrame86>()

    private var candidateStartTimeMs: Long = 0L
    private var signStartTimeMs: Long = 0L
    private var quietStartTimeMs: Long = 0L
    private var endReason: String = "NONE"

    /**
     * معالجة إطار جديد وتحديث حالة الإشارة
     * يُعيد مقطع SignSegment عند اكتمال إشارة وانتقالها لـ PROCESSING
     */
    fun processFrame(
        frame: KeypointFrame86,
        onSegmentCompleted: (SignSegment) -> Unit
    ): MotionFrameFeatures {
        val isIdle = (state == SignState.IDLE)
        val motion = motionAnalyzer.computeMotion(frame, isIdle)
        val now = frame.timestampMs

        when (state) {
            SignState.IDLE -> {
                // الاحتفاظ بـ Pre-Roll Buffer
                if (preRollBuffer.size >= preRollMaxFrames) {
                    preRollBuffer.removeFirst()
                }
                preRollBuffer.addLast(frame)

                // فحص مرشح بداية الحركة
                if (motion.activeHandMotion > motion.startThreshold) {
                    state = SignState.STARTING
                    candidateStartTimeMs = now
                }
            }

            SignState.STARTING -> {
                preRollBuffer.addLast(frame)

                // إذا استمرت الحركة لأكثر من candidateDurationMs نتأكد من بداية الإشارة
                if (motion.activeHandMotion > motion.endThreshold) {
                    val duration = now - candidateStartTimeMs
                    if (duration >= candidateDurationMs) {
                        state = SignState.SIGNING
                        signStartTimeMs = candidateStartTimeMs
                        activeSegmentFrames.clear()
                        // إضافة فريمات الـ Pre-roll كاملة لالتقاط بداية المسار
                        activeSegmentFrames.addAll(preRollBuffer)
                        preRollBuffer.clear()
                    }
                } else {
                    // حركة عابرة (Jitter): العودة لـ IDLE
                    state = SignState.IDLE
                }
            }

            SignState.SIGNING -> {
                activeSegmentFrames.add(frame)

                // سقف الأمان الأقصى لمنع التعليق
                val currentDuration = now - signStartTimeMs
                if (currentDuration >= maxSignDurationMs) {
                    endReason = "MAX_DURATION"
                    finalizeSegment(now, onSegmentCompleted)
                    return motion
                }

                // فحص هدوء الحركة
                if (motion.activeHandMotion < motion.endThreshold) {
                    state = SignState.ENDING
                    quietStartTimeMs = now
                }
            }

            SignState.ENDING -> {
                // إضافة فريمات الـ Post-Roll للحفاظ على الـ final handshape
                activeSegmentFrames.add(frame)

                // سقف الأمان
                val currentDuration = now - signStartTimeMs
                if (currentDuration >= maxSignDurationMs) {
                    endReason = "MAX_DURATION"
                    finalizeSegment(now, onSegmentCompleted)
                    return motion
                }

                // إذا عادت الحركة بقوة قبل اكتمال الهدوء، نستأنف الإشارة (Hysteresis)
                if (motion.activeHandMotion > motion.startThreshold) {
                    state = SignState.SIGNING
                } else {
                    val quietDuration = now - quietStartTimeMs
                    if (quietDuration >= quietDurationMs) {
                        endReason = "MOTION_QUIET"
                        finalizeSegment(now, onSegmentCompleted)
                    }
                }
            }

            SignState.PROCESSING -> {
                // أثناء المعالجة، نستمر بملء Pre-Roll للإشارة القادمة دون انتظار
                if (preRollBuffer.size >= preRollMaxFrames) {
                    preRollBuffer.removeFirst()
                }
                preRollBuffer.addLast(frame)
            }
        }

        return motion
    }

    private fun finalizeSegment(endTimeMs: Long, onSegmentCompleted: (SignSegment) -> Unit) {
        val totalDuration = endTimeMs - signStartTimeMs

        if (totalDuration >= minSignDurationMs && activeSegmentFrames.isNotEmpty()) {
            val segment = SignSegment(
                frames = activeSegmentFrames.toList(),
                durationMs = totalDuration,
                frameCount = activeSegmentFrames.size,
                startTimestampMs = signStartTimeMs,
                endTimestampMs = endTimeMs,
                endReason = endReason
            )
            state = SignState.PROCESSING
            onSegmentCompleted(segment)
        } else {
            // إشارة قصيرة جداً (أقل من 250ms)، نلغيها
            state = SignState.IDLE
        }
        activeSegmentFrames.clear()
    }

    /**
     * إرجاع الحالة إلى IDLE بعد انتهاء استنتاج الموديل
     */
    fun onProcessingFinished() {
        state = SignState.IDLE
        activeSegmentFrames.clear()
        endReason = "NONE"
    }

    /**
     * إنهاء إجباري للإشارة الحالية
     */
    fun forceFinalize(reason: String = "FORCE_STOP", onSegmentCompleted: (SignSegment) -> Unit) {
        if (state == SignState.SIGNING || state == SignState.ENDING) {
            endReason = reason
            finalizeSegment(System.currentTimeMillis(), onSegmentCompleted)
        } else {
            state = SignState.IDLE
            activeSegmentFrames.clear()
        }
    }

    fun reset() {
        state = SignState.IDLE
        preRollBuffer.clear()
        activeSegmentFrames.clear()
        motionAnalyzer.reset()
        endReason = "NONE"
    }
}
