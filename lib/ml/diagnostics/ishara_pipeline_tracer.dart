import 'package:flutter/foundation.dart';

/// مراحل الـ Pipeline الرئيسية للتتبع الدقيق
enum PipelineStage {
  idle('READY', 'في وضع الاستعداد'),
  systemInit('STAGE 1: SYSTEM HEALTH', 'فحص جاهزية النظام والخدمات'),
  cameraIngestion('STAGE 2: CAMERA INGESTION', 'استقبال إطارات الكاميرا'),
  landmarkExtraction('STAGE 3: VISION EXTRACTION', 'استخراج المعالم والأيدي والوجه'),
  keypointNormalization('STAGE 4: 86-PT NORMALIZATION', 'تطبيع النقاط الـ 86 والتعويض'),
  ringBuffer('STAGE 5: RING BUFFER (128)', 'تجميع نافذة الـ 128 إطاراً'),
  modelInputValidation('STAGE 6: MODEL INPUT TENSOR', 'تجهيز وفحص مصفوفة [1,128,86,2]'),
  tfliteInference('STAGE 7: TFLITE INFERENCE', 'تنفيذ استنتاج الموديل [1,29,684]'),
  ctcDecoding('STAGE 8: CTC DECODING', 'فك ترميز Greedy CTC'),
  vocabMapping('STAGE 9: VOCAB & GLOSS', 'ربط المفردات واستخراج الكلمات'),
  completed('STAGE 10: SUCCESS', 'اكتملت الترجمة بنجاح'),
  failed('STAGE: ERROR ENCOUNTERED', 'فشل في إحدى المراحل');

  final String title;
  final String description;
  const PipelineStage(this.title, this.description);
}

/// لقطة تشخيصية لحظية لمرحلة استخراج المعالم
class LandmarkExtractionTelemetry {
  final bool personDetected;
  final int headPoints;
  final int upperBodyPoints;
  final int faceMeshPoints;
  final int lipsPoints;
  final int rightHandPoints;
  final int leftHandPoints;
  final int rawDetectedCount;
  final int imputedCount;
  final double fps;

  const LandmarkExtractionTelemetry({
    this.personDetected = false,
    this.headPoints = 0,
    this.upperBodyPoints = 0,
    this.faceMeshPoints = 0,
    this.lipsPoints = 0,
    this.rightHandPoints = 0,
    this.leftHandPoints = 0,
    this.rawDetectedCount = 0,
    this.imputedCount = 0,
    this.fps = 0.0,
  });
}

/// لقطة تشخيصية لمصفوفة الإدخال [1, 128, 86, 2]
class ModelInputTelemetry {
  final List<int> shape;
  final int totalFloats;
  final int nanCount;
  final int infCount;
  final double minVal;
  final double maxVal;
  final double meanVal;
  final double nonZeroPercent;
  final bool handsBackwardFilled;

  const ModelInputTelemetry({
    this.shape = const [1, 128, 86, 2],
    this.totalFloats = 22016,
    this.nanCount = 0,
    this.infCount = 0,
    this.minVal = 0.0,
    this.maxVal = 0.0,
    this.meanVal = 0.0,
    this.nonZeroPercent = 0.0,
    this.handsBackwardFilled = true,
  });

  factory ModelInputTelemetry.fromFlatData(
    Float32List flatData, {
    List<int> shape = const [1, 128, 86, 2],
    bool handsBackwardFilled = true,
  }) {
    int nanCount = 0;
    int infCount = 0;
    int nonZeroCount = 0;
    double minVal = double.infinity;
    double maxVal = -double.infinity;
    double sum = 0.0;

    for (int i = 0; i < flatData.length; i++) {
      final v = flatData[i];
      if (v.isNaN) {
        nanCount++;
      } else if (v.isInfinite) {
        infCount++;
      } else {
        if (v < minVal) minVal = v;
        if (v > maxVal) maxVal = v;
        sum += v;
        if (v.abs() > 1e-6) nonZeroCount++;
      }
    }

    final double mean = flatData.isNotEmpty ? (sum / flatData.length) : 0.0;
    final double nonZeroPct =
        flatData.isNotEmpty ? (nonZeroCount * 100.0 / flatData.length) : 0.0;

    return ModelInputTelemetry(
      shape: shape,
      totalFloats: flatData.length,
      nanCount: nanCount,
      infCount: infCount,
      minVal: minVal.isInfinite ? 0.0 : minVal,
      maxVal: maxVal.isInfinite ? 0.0 : maxVal,
      meanVal: mean,
      nonZeroPercent: nonZeroPct,
      handsBackwardFilled: handsBackwardFilled,
    );
  }
}

/// لقطة تشخيصية لمخرجات TFLite [1, 29, 684] و CTC
class ModelOutputTelemetry {
  final int inferenceTimeMs;
  final List<int> outputShape;
  final int nanCount;
  final int infCount;
  final double minVal;
  final double maxVal;
  final double meanVal;
  final double stdDev;
  final List<int> rawArgmax;
  final int blankCount;
  final List<int> uniqueNonBlankClasses;
  final List<int> ctcDecodedIds;
  final List<String> glosses;

  const ModelOutputTelemetry({
    this.inferenceTimeMs = 0,
    this.outputShape = const [1, 29, 684],
    this.nanCount = 0,
    this.infCount = 0,
    this.minVal = 0.0,
    this.maxVal = 0.0,
    this.meanVal = 0.0,
    this.stdDev = 0.0,
    this.rawArgmax = const [],
    this.blankCount = 0,
    this.uniqueNonBlankClasses = const [],
    this.ctcDecodedIds = const [],
    this.glosses = const [],
  });
}

/// IsharaPipelineTracer
/// المحرك المركزي الشامل لتتبع وتشخيص مسار الإشارة لحظة بلحظة:
/// يسجل كافة المدخلات والمخرجات والأبعاد والإحصائيات والأخطاء
/// ويولد تقريراً تشخيصياً نصياً شاملاً يمكن للمستخدم نسخه ولصقه بنقرة واحدة.
class IsharaPipelineTracer {
  static final IsharaPipelineTracer instance = IsharaPipelineTracer._internal();
  IsharaPipelineTracer._internal();

  PipelineStage currentStage = PipelineStage.idle;
  DateTime? testStartTime;
  DateTime? testEndTime;

  // ── 1. حالة النظام (System Health) ──
  bool cameraReady = false;
  bool cameraStreaming = false;
  String cameraLens = 'unknown';
  int cameraWidth = 0;
  int cameraHeight = 0;

  bool poseDetectorReady = false;
  bool faceMeshReady = false;
  bool handDetectorReady = false;

  bool tfliteReady = false;
  String tfliteState = 'NOT_LOADED';
  double modelSizeMb = 0.0;
  List<int> expectedInputShape = const [1, 128, 86, 2];
  List<int> expectedOutputShape = const [1, 29, 684];
  String? tfliteInitError;

  bool vocabReady = false;
  int vocabCount = 0;
  String? vocabInitError;

  // ── 2. استقبال وتدفق الإطارات (Camera Ingestion) ──
  int totalCameraFramesReceived = 0;
  int totalCameraFramesDropped = 0;
  double liveFps = 0.0;

  // ── 3 & 4. المعالم والتطبيع (Vision & Normalization) ──
  LandmarkExtractionTelemetry latestLandmarks = const LandmarkExtractionTelemetry();

  // ── 5. الـ Ring Buffer ──
  int ringBufferCount = 0;
  int ringBufferTarget = 128;
  int ringBufferFramesAdded = 0;
  int ringBufferFramesSkippedNoPerson = 0;
  int ringBufferDuplicatesRejected = 0;
  int? oldestSequenceId;
  int? newestSequenceId;

  // ── 6. مصفوفة الإدخال للموديل ──
  ModelInputTelemetry? modelInputTelemetry;

  // ── 7 & 8 & 9. الموديل و CTC والقاموس ──
  ModelOutputTelemetry? modelOutputTelemetry;
  String finalGlossResult = '';

  // ── 10. تشخيص الأخطاء (Error Diagnostics) ──
  bool hasError = false;
  String? errorStage;
  String? errorMessage;
  String? errorStackTrace;

  /// إعادة تعيين التتبع لبدء اختبار جديد
  void startNewSession() {
    testStartTime = DateTime.now();
    testEndTime = null;
    currentStage = PipelineStage.cameraIngestion;
    hasError = false;
    errorStage = null;
    errorMessage = null;
    errorStackTrace = null;
    ringBufferCount = 0;
    ringBufferFramesAdded = 0;
    ringBufferFramesSkippedNoPerson = 0;
    ringBufferDuplicatesRejected = 0;
    modelInputTelemetry = null;
    modelOutputTelemetry = null;
    finalGlossResult = '';
  }

  /// تسجيل خطأ في أي مرحلة من المراحل
  void recordError({
    required PipelineStage stage,
    required dynamic error,
    StackTrace? stackTrace,
  }) {
    hasError = true;
    currentStage = PipelineStage.failed;
    errorStage = stage.title;
    errorMessage = error.toString();
    errorStackTrace = stackTrace?.toString();
    testEndTime = DateTime.now();
  }

  /// تحديث حالة فحص صحة النظام
  void updateSystemHealth({
    required bool cameraReady,
    required bool cameraStreaming,
    required String cameraLens,
    required int cameraWidth,
    required int cameraHeight,
    required bool poseReady,
    required bool faceReady,
    required bool handReady,
    required bool tfliteReady,
    required String tfliteState,
    required double modelSizeMb,
    String? tfliteError,
    required bool vocabReady,
    required int vocabCount,
    String? vocabError,
  }) {
    this.cameraReady = cameraReady;
    this.cameraStreaming = cameraStreaming;
    this.cameraLens = cameraLens;
    this.cameraWidth = cameraWidth;
    this.cameraHeight = cameraHeight;
    poseDetectorReady = poseReady;
    faceMeshReady = faceReady;
    handDetectorReady = handReady;
    this.tfliteReady = tfliteReady;
    this.tfliteState = tfliteState;
    this.modelSizeMb = modelSizeMb;
    tfliteInitError = tfliteError;
    this.vocabReady = vocabReady;
    this.vocabCount = vocabCount;
    vocabInitError = vocabError;
  }

  /// تحديث إحصائيات المعالم اللحظية
  void updateLandmarks(LandmarkExtractionTelemetry telemetry) {
    latestLandmarks = telemetry;
    liveFps = telemetry.fps;
  }

  /// تحديث تقدم الـ Ring Buffer أثناء جمع الإطارات
  void updateRingBufferProgress({
    required int currentCount,
    required int framesAdded,
    required int framesSkippedNoPerson,
    required int duplicatesRejected,
    int? oldestId,
    int? newestId,
  }) {
    ringBufferCount = currentCount;
    ringBufferFramesAdded = framesAdded;
    ringBufferFramesSkippedNoPerson = framesSkippedNoPerson;
    ringBufferDuplicatesRejected = duplicatesRejected;
    oldestSequenceId = oldestId;
    newestSequenceId = newestId;
  }

  /// توليد التقرير التشخيصي الكامل بصيغة Markdown سهلة القراءة والنسخ
  String toMarkdownReport() {
    final buf = StringBuffer();
    final now = DateTime.now();
    final durationMs = testStartTime != null
        ? (testEndTime ?? now).difference(testStartTime!).inMilliseconds
        : 0;

    buf.writeln('==================================================');
    buf.writeln('      ISHARA PIPELINE TELEMETRY & DIAGNOSTICS      ');
    buf.writeln('==================================================');
    buf.writeln('Generated At: ${now.toIso8601String().replaceFirst('T', ' ').substring(0, 19)}');
    buf.writeln('Session Status: ${hasError ? "❌ FAILED" : (finalGlossResult.isNotEmpty ? "✅ SUCCESS" : "⏳ IN_PROGRESS")}');
    buf.writeln('Current Stage: ${currentStage.title} (${currentStage.description})');
    buf.writeln('Session Duration: ${durationMs} ms (${(durationMs / 1000.0).toStringAsFixed(1)} s)');
    buf.writeln('');

    // ── 1. SYSTEM HEALTH ──
    buf.writeln('--------------------------------------------------');
    buf.writeln('1. SYSTEM HEALTH & DETECTORS');
    buf.writeln('--------------------------------------------------');
    buf.writeln('• Camera: ${cameraReady ? "✅ READY" : "❌ NOT READY"} | Streaming: ${cameraStreaming ? "YES" : "NO"}');
    buf.writeln('  - Lens: $cameraLens | Resolution: ${cameraWidth}x$cameraHeight');
    buf.writeln('• ML Kit Pose Detector: ${poseDetectorReady ? "✅ READY" : "❌ FAILED"}');
    buf.writeln('• ML Kit Face Mesh:      ${faceMeshReady ? "✅ READY" : "❌ FAILED"}');
    buf.writeln('• MediaPipe Hands:       ${handDetectorReady ? "✅ READY" : "❌ FAILED"}');
    buf.writeln('• TFLite Engine:         ${tfliteReady ? "✅ READY" : "❌ ERROR ($tfliteState)"}');
    buf.writeln('  - Model Size: ${modelSizeMb.toStringAsFixed(2)} MB');
    buf.writeln('  - Tensors: In $expectedInputShape -> Out $expectedOutputShape');
    if (tfliteInitError != null) {
      buf.writeln('  - ⚠️ TFLite Init Error: $tfliteInitError');
    }
    buf.writeln('• Vocabulary Service:   ${vocabReady ? "✅ LOADED ($vocabCount entries)" : "❌ FAILED"}');
    if (vocabInitError != null) {
      buf.writeln('  - ⚠️ Vocab Init Error: $vocabInitError');
    }
    buf.writeln('');

    // ── 2. CAMERA INGESTION ──
    buf.writeln('--------------------------------------------------');
    buf.writeln('2. CAMERA STREAM INGESTION');
    buf.writeln('--------------------------------------------------');
    buf.writeln('• Live Processing FPS: ${liveFps.toStringAsFixed(1)} FPS');
    buf.writeln('• Total Frames Ingested: $totalCameraFramesReceived');
    buf.writeln('• Total Frames Dropped:  $totalCameraFramesDropped');
    buf.writeln('');

    // ── 3 & 4. VISION EXTRACTION & NORMALIZATION ──
    buf.writeln('--------------------------------------------------');
    buf.writeln('3 & 4. LANDMARKS EXTRACTION & 86-KEYPOINTS');
    buf.writeln('--------------------------------------------------');
    buf.writeln('• Person Detected:      ${latestLandmarks.personDetected ? "✅ YES" : "⚠️ NO PERSON"}');
    buf.writeln('• Head Pose Points:     ${latestLandmarks.headPoints} / 11');
    buf.writeln('• Upper Body Points:    ${latestLandmarks.upperBodyPoints} / 14');
    buf.writeln('• Face Mesh Points:     ${latestLandmarks.faceMeshPoints} / 468');
    buf.writeln('• Lips Extracted:       ${latestLandmarks.lipsPoints} / 19');
    buf.writeln('• Right Hand Points:    ${latestLandmarks.rightHandPoints} / 21 ${latestLandmarks.rightHandPoints >= 10 ? "✅" : "⚠️"}');
    buf.writeln('• Left Hand Points:     ${latestLandmarks.leftHandPoints} / 21 ${latestLandmarks.leftHandPoints >= 10 ? "✅" : "⚠️"}');
    buf.writeln('• Raw Detected Points:  ${latestLandmarks.rawDetectedCount} / 86');
    buf.writeln('• Imputed Points:       ${latestLandmarks.imputedCount} / 86');
    buf.writeln('');

    // ── 5. RING BUFFER (128 WINDOW) ──
    buf.writeln('--------------------------------------------------');
    buf.writeln('5. RING BUFFER STATUS (128 WINDOW)');
    buf.writeln('--------------------------------------------------');
    buf.writeln('• Buffer Frame Count:      $ringBufferCount / $ringBufferTarget (${(ringBufferCount * 100.0 / ringBufferTarget).clamp(0.0, 100.0).toStringAsFixed(1)}%)');
    buf.writeln('• Frames Added Since Test: $ringBufferFramesAdded');
    buf.writeln('• Frames Skipped (No Person): $ringBufferFramesSkippedNoPerson');
    buf.writeln('• Duplicate Timestamps Rejected: $ringBufferDuplicatesRejected');
    if (oldestSequenceId != null && newestSequenceId != null) {
      buf.writeln('• Sequence IDs: Oldest #$oldestSequenceId -> Newest #$newestSequenceId');
    }
    buf.writeln('');

    // ── 6. MODEL INPUT TENSOR ──
    buf.writeln('--------------------------------------------------');
    buf.writeln('6. MODEL INPUT TENSOR [1, 128, 86, 2]');
    buf.writeln('--------------------------------------------------');
    if (modelInputTelemetry != null) {
      final inp = modelInputTelemetry!;
      buf.writeln('• Tensor Shape:       ${inp.shape} (${inp.totalFloats} floats)');
      buf.writeln('• NaN Count:          ${inp.nanCount} ${inp.nanCount == 0 ? "✅ (ZERO)" : "❌ ERROR"}');
      buf.writeln('• Infinity Count:     ${inp.infCount} ${inp.infCount == 0 ? "✅ (ZERO)" : "❌ ERROR"}');
      buf.writeln('• Hands Backward-Fill: ${inp.handsBackwardFilled ? "✅ APPLIED" : "NO"}');
      buf.writeln('• Value Range:        [${inp.minVal.toStringAsFixed(4)} .. ${inp.maxVal.toStringAsFixed(4)}]');
      buf.writeln('• Mean Value:         ${inp.meanVal.toStringAsFixed(4)}');
      buf.writeln('• Active Values:      ${inp.nonZeroPercent.toStringAsFixed(1)}% non-zero');
    } else {
      buf.writeln('• Status: NOT CREATED YET (Awaiting 128 frames)');
    }
    buf.writeln('');

    // ── 7. TFLITE INFERENCE ──
    buf.writeln('--------------------------------------------------');
    buf.writeln('7. TFLITE INFERENCE [1, 29, 684]');
    buf.writeln('--------------------------------------------------');
    if (modelOutputTelemetry != null) {
      final out = modelOutputTelemetry!;
      buf.writeln('• Inference Time:     ${out.inferenceTimeMs} ms');
      buf.writeln('• Output Tensor Shape: ${out.outputShape}');
      buf.writeln('• Output NaN/Inf:     NaN: ${out.nanCount}, Inf: ${out.infCount} ${out.nanCount == 0 && out.infCount == 0 ? "✅" : "❌"}');
      buf.writeln('• Output Value Range: [${out.minVal.toStringAsFixed(3)} .. ${out.maxVal.toStringAsFixed(3)}]');
      buf.writeln('• Output Mean / Std:  Mean: ${out.meanVal.toStringAsFixed(3)}, StdDev: ${out.stdDev.toStringAsFixed(3)}');
      buf.writeln('• Raw Argmax (29 timesteps):');
      buf.writeln('  ${out.rawArgmax}');
      buf.writeln('• Blank Class (0) Count: ${out.blankCount} / 29');
      buf.writeln('• Unique Non-Blank Classes: ${out.uniqueNonBlankClasses}');
    } else {
      buf.writeln('• Status: NOT EXECUTED YET');
    }
    buf.writeln('');

    // ── 8 & 9. CTC & VOCABULARY ──
    buf.writeln('--------------------------------------------------');
    buf.writeln('8 & 9. CTC DECODING & VOCABULARY MAPPING');
    buf.writeln('--------------------------------------------------');
    if (modelOutputTelemetry != null) {
      final out = modelOutputTelemetry!;
      buf.writeln('• Decoded CTC IDs: ${out.ctcDecodedIds}');
      buf.writeln('• Arabic Glosses:  ${out.glosses}');
      buf.writeln('• Final Display:   "$finalGlossResult"');
    } else {
      buf.writeln('• Status: PENDING INFERENCE');
    }
    buf.writeln('');

    // ── 10. ERROR DIAGNOSTICS & STACK TRACE ──
    if (hasError) {
      buf.writeln('==================================================');
      buf.writeln('              ⚠️ EXCEPTION TRACE ⚠️               ');
      buf.writeln('==================================================');
      buf.writeln('• Failed Stage: $errorStage');
      buf.writeln('• Error Message:');
      buf.writeln('$errorMessage');
      if (errorStackTrace != null && errorStackTrace!.isNotEmpty) {
        buf.writeln('• Stack Trace:');
        buf.writeln(errorStackTrace);
      }
      buf.writeln('==================================================');
    } else {
      buf.writeln('==================================================');
      buf.writeln('             NO ERRORS DETECTED ✅                ');
      buf.writeln('==================================================');
    }

    return buf.toString();
  }
}
