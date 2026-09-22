package com.Ishara.iq.ishara.model

import android.content.Context
import android.content.res.AssetFileDescriptor
import android.util.Log
import io.flutter.FlutterInjector
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * نتيجة الاستنتاج الحقيقي للنموذج (NativeInferenceResult)
 */
data class NativeInferenceResult(
    val isSuccess: Boolean,
    val rawArgmax: IntArray,
    val decodedIds: IntArray,
    val glosses: List<String>,
    val inferenceTimeMs: Long,
    val errorMessage: String? = null
) {
    fun toMap(): Map<String, Any?> {
        return mapOf(
            "isSuccess" to isSuccess,
            "rawArgmax" to rawArgmax.toList(),
            "decodedIds" to decodedIds.toList(),
            "glosses" to glosses,
            "inferenceTimeMs" to inferenceTimeMs,
            "errorMessage" to errorMessage
        )
    }
}

/**
 * مشغل نموذج TFLite الأصلي (IsharaModelRunner)
 * يضمن:
 * 1. تشغيل الاستنتاج على خيط مستقل بعيداً عن الكاميرا ومعالجة المعالم.
 * 2. التحقق الصارم من مدخلات الموديل (FLOAT32, [1,128,86,2], NaN=0, Inf=0).
 * 3. منع الاستنتاج المتداخل (AtomicBoolean inferenceRunning).
 * 4. تطبيق Greedy CTC Decoder وربط الكلمات من القاموس.
 */
class IsharaModelRunner(
    private val context: Context,
    val vocabLoader: VocabularyLoader = VocabularyLoader(context)
) {

    companion object {
        private const val TAG = "IsharaModelRunner"
        private const val MODEL_ASSET_PATH = "assets/models/ishara_model.tflite"

        const val BATCH_SIZE = 1
        const val TIME_STEPS = 128
        const val KEYPOINTS = 86
        const val CHANNELS = 2
        const val TOTAL_INPUT_ELEMENTS = BATCH_SIZE * TIME_STEPS * KEYPOINTS * CHANNELS // 22016

        const val OUTPUT_TIME_STEPS = 29
        const val OUTPUT_CLASSES = 684
        const val TOTAL_OUTPUT_ELEMENTS = BATCH_SIZE * OUTPUT_TIME_STEPS * OUTPUT_CLASSES // 19836
    }

    private var interpreter: Interpreter? = null
    private val modelExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val isInferencing = AtomicBoolean(false)

    var isModelLoaded: Boolean = false
        private set

    // مخازن ذاكرة مباشرة ومُسبقة الحجز لتجنب تخصيص الذاكرة مع كل إشارة
    private val inputBuffer: ByteBuffer = ByteBuffer.allocateDirect(TOTAL_INPUT_ELEMENTS * 4).apply {
        order(ByteOrder.nativeOrder())
    }

    private val outputBuffer: ByteBuffer = ByteBuffer.allocateDirect(TOTAL_OUTPUT_ELEMENTS * 4).apply {
        order(ByteOrder.nativeOrder())
    }

    /**
     * تهيئة وتحميل الموديل والقاموس
     */
    fun initialize(onInitialized: ((Boolean) -> Unit)? = null) {
        modelExecutor.execute {
            try {
                // 1. تحميل القاموس أولاً
                vocabLoader.loadVocabulary()

                // 2. قراءة ملف الموديل عبر AssetFileDescriptor
                val assetManager = context.assets
                val lookupKey = try {
                    FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(MODEL_ASSET_PATH)
                } catch (e: Exception) {
                    "flutter_assets/$MODEL_ASSET_PATH"
                }

                val afd: AssetFileDescriptor = try {
                    assetManager.openFd(lookupKey)
                } catch (e: Exception) {
                    try {
                        assetManager.openFd("flutter_assets/$MODEL_ASSET_PATH")
                    } catch (e2: Exception) {
                        assetManager.openFd(MODEL_ASSET_PATH)
                    }
                }

                val inputStream = FileInputStream(afd.fileDescriptor)
                val fileChannel = inputStream.channel
                val startOffset = afd.startOffset
                val declaredLength = afd.declaredLength
                val modelByteBuffer = fileChannel.map(FileChannel.MapMode.READ_ONLY, startOffset, declaredLength)

                // 3. ضبط خيارات TFLite (تفعيل Multi-threading بـ 2 أو 4 خيوط)
                val options = Interpreter.Options().apply {
                    setNumThreads(4)
                    setCancellable(true)
                }

                interpreter = Interpreter(modelByteBuffer, options)
                isModelLoaded = true
                Log.i(TAG, "TFLite Model loaded successfully: input=[1, 128, 86, 2], output=[1, 29, 684].")
                onInitialized?.invoke(true)
            } catch (e: Exception) {
                Log.e(TAG, "Error initializing TFLite Model: ${e.message}", e)
                isModelLoaded = false
                onInitialized?.invoke(false)
            }
        }
    }

    /**
     * تشغيل استنتاج الموديل على مصفوفة الإشارة المستوفاة [1, 128, 86, 2]
     */
    fun runInference(
        inputFloats: FloatArray,
        onResult: (NativeInferenceResult) -> Unit
    ) {
        val tflite = interpreter
        if (tflite == null || !isModelLoaded) {
            onResult(
                NativeInferenceResult(
                    isSuccess = false,
                    rawArgmax = intArrayOf(),
                    decodedIds = intArrayOf(),
                    glosses = emptyList(),
                    inferenceTimeMs = 0,
                    errorMessage = "Model not initialized"
                )
            )
            return
        }

        // 1. التحقق الصارم من المدخلات (FLOAT32, [1,128,86,2], NaN=0, Inf=0)
        if (inputFloats.size != TOTAL_INPUT_ELEMENTS) {
            onResult(
                NativeInferenceResult(
                    isSuccess = false,
                    rawArgmax = intArrayOf(),
                    decodedIds = intArrayOf(),
                    glosses = emptyList(),
                    inferenceTimeMs = 0,
                    errorMessage = "Invalid input shape size: ${inputFloats.size} != $TOTAL_INPUT_ELEMENTS"
                )
            )
            return
        }

        // فحص NaN و Infinity
        var hasNanOrInf = false
        for (i in 0 until TOTAL_INPUT_ELEMENTS) {
            val v = inputFloats[i]
            if (v.isNaN() || v.isInfinite()) {
                hasNanOrInf = true
                break
            }
        }
        if (hasNanOrInf) {
            onResult(
                NativeInferenceResult(
                    isSuccess = false,
                    rawArgmax = intArrayOf(),
                    decodedIds = intArrayOf(),
                    glosses = emptyList(),
                    inferenceTimeMs = 0,
                    errorMessage = "Validation error: Input contains NaN or Infinity"
                )
            )
            return
        }

        // 2. منع الاستنتاج المتداخل (AtomicBoolean)
        if (!isInferencing.compareAndSet(false, true)) {
            Log.w(TAG, "Inference is already running, skipping overlapping request.")
            return
        }

        modelExecutor.execute {
            val startTime = System.currentTimeMillis()
            try {
                // 3. نسخ المدخلات إلى Direct ByteBuffer
                inputBuffer.rewind()
                val floatBuffer = inputBuffer.asFloatBuffer()
                floatBuffer.put(inputFloats)

                // 4. تشغيل الموديل
                outputBuffer.rewind()
                tflite.run(inputBuffer, outputBuffer)

                val inferenceDuration = System.currentTimeMillis() - startTime

                // 5. استخراج الـ Argmax عبر الـ 29 خطوة زمنية
                outputBuffer.rewind()
                val outFloats = outputBuffer.asFloatBuffer()
                val rawArgmax = IntArray(OUTPUT_TIME_STEPS)

                for (step in 0 until OUTPUT_TIME_STEPS) {
                    var maxVal = Float.NEGATIVE_INFINITY
                    var maxIdx = 0
                    for (c in 0 until OUTPUT_CLASSES) {
                        val score = outFloats.get()
                        if (score > maxVal) {
                            maxVal = score
                            maxIdx = c
                        }
                    }
                    rawArgmax[step] = maxIdx
                }

                // 6. تطبيق CTC Decoding
                val ctcResult = CtcDecoder.decodeArgmax(rawArgmax)

                // 7. ربط المفردات
                val glosses = vocabLoader.mapIdsToGlosses(ctcResult.decodedIds)

                val result = NativeInferenceResult(
                    isSuccess = true,
                    rawArgmax = rawArgmax,
                    decodedIds = ctcResult.decodedIds,
                    glosses = glosses,
                    inferenceTimeMs = inferenceDuration
                )

                onResult(result)
            } catch (e: Exception) {
                Log.e(TAG, "Inference execution failed: ${e.message}", e)
                onResult(
                    NativeInferenceResult(
                        isSuccess = false,
                        rawArgmax = intArrayOf(),
                        decodedIds = intArrayOf(),
                        glosses = emptyList(),
                        inferenceTimeMs = System.currentTimeMillis() - startTime,
                        errorMessage = e.message
                    )
                )
            } finally {
                isInferencing.set(false)
            }
        }
    }

    fun dispose() {
        interpreter?.close()
        interpreter = null
        modelExecutor.shutdown()
    }
}
