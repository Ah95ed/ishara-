import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:ishara/ml/ctc/ishara_ctc_decoder.dart';
import 'package:ishara/models/ctc_vocab_result.dart';

/// نتيجة استنتاج تسلسل حقيقي واحد (Test A أو Test B)
class SingleRealInferenceResult {
  final String testLabel; // 'TEST A' أو 'TEST B'
  final DateTime capturedAt;
  final bool isSuccess;
  final String? errorCode;
  final String? errorMessage;
  final int inferenceTimeMs;

  // ── خصائص ومقاييس الإدخال الحقيقي (Real Input) ──
  final int bufferCount; // 128
  final List<int> inputShape; // [1, 128, 86, 2]
  final int inputNanCount;
  final int inputInfCount;
  final bool isChronological;
  final int oldestFrameSequenceId;
  final int newestFrameSequenceId;

  // ── جودة التسلسل (Sequence Quality Metadata) ──
  final double rawKeypointCoveragePct;
  final double imputationPct;
  final double rightHandCoveragePct;
  final double leftHandCoveragePct;
  final double lipsCoveragePct;
  final double bodyCoveragePct;

  // ── مخرجات الموديل الحقيقية الخام (Raw Model Output) ──
  final List<int> outputShape; // [1, 29, 684]
  final int outputNanCount;
  final int outputInfCount;
  final double outputMin;
  final double outputMax;
  final double outputMean;
  final double outputStdDev;

  // ── التشخيص الخام للفئات (Raw Argmax & Classes) ──
  final List<int> rawArgmax; // 29 integers
  final List<int> uniqueClasses;
  final int blankTop1Count; // عدد الفئات 0 من 29

  // ── مصفوفة المخرجات المسطحة للمقارنة وحساب الفروق الدقيقة (19,836 Floats) ──
  final Float32List flatOutput;

  // ── نتيجة فك تشفير CTC (CTC Decode Result) ──
  final CtcDecodeResult? ctcResult;

  // ── نتيجة فك التشفير وربط المفردات (CTC + Vocabulary Result) ──
  final CtcVocabResult? ctcVocabResult;

  const SingleRealInferenceResult({
    required this.testLabel,
    required this.capturedAt,
    required this.isSuccess,
    this.errorCode,
    this.errorMessage,
    required this.inferenceTimeMs,
    required this.bufferCount,
    required this.inputShape,
    required this.inputNanCount,
    required this.inputInfCount,
    required this.isChronological,
    required this.oldestFrameSequenceId,
    required this.newestFrameSequenceId,
    required this.rawKeypointCoveragePct,
    required this.imputationPct,
    required this.rightHandCoveragePct,
    required this.leftHandCoveragePct,
    required this.lipsCoveragePct,
    required this.bodyCoveragePct,
    required this.outputShape,
    required this.outputNanCount,
    required this.outputInfCount,
    required this.outputMin,
    required this.outputMax,
    required this.outputMean,
    required this.outputStdDev,
    required this.rawArgmax,
    required this.uniqueClasses,
    required this.blankTop1Count,
    required this.flatOutput,
    this.ctcResult,
    this.ctcVocabResult,
  });

  /// إنشاء نتيجة فاشلة مع كود خطأ محدد قبل تشغيل الموديل
  factory SingleRealInferenceResult.failure({
    required String testLabel,
    required DateTime capturedAt,
    required String errorCode,
    required String errorMessage,
    int bufferCount = 0,
    List<int> inputShape = const [1, 128, 86, 2],
    int inputNanCount = 0,
    int inputInfCount = 0,
    bool isChronological = false,
    int oldestFrameSequenceId = 0,
    int newestFrameSequenceId = 0,
    double rawKeypointCoveragePct = 0.0,
    double imputationPct = 0.0,
    double rightHandCoveragePct = 0.0,
    double leftHandCoveragePct = 0.0,
    double lipsCoveragePct = 0.0,
    double bodyCoveragePct = 0.0,
  }) {
    return SingleRealInferenceResult(
      testLabel: testLabel,
      capturedAt: capturedAt,
      isSuccess: false,
      errorCode: errorCode,
      errorMessage: errorMessage,
      inferenceTimeMs: 0,
      bufferCount: bufferCount,
      inputShape: inputShape,
      inputNanCount: inputNanCount,
      inputInfCount: inputInfCount,
      isChronological: isChronological,
      oldestFrameSequenceId: oldestFrameSequenceId,
      newestFrameSequenceId: newestFrameSequenceId,
      rawKeypointCoveragePct: rawKeypointCoveragePct,
      imputationPct: imputationPct,
      rightHandCoveragePct: rightHandCoveragePct,
      leftHandCoveragePct: leftHandCoveragePct,
      lipsCoveragePct: lipsCoveragePct,
      bodyCoveragePct: bodyCoveragePct,
      outputShape: const [1, 29, 684],
      outputNanCount: 0,
      outputInfCount: 0,
      outputMin: 0.0,
      outputMax: 0.0,
      outputMean: 0.0,
      outputStdDev: 0.0,
      rawArgmax: const [],
      uniqueClasses: const [],
      blankTop1Count: 0,
      flatOutput: Float32List(0),
    );
  }
}

/// نتيجة المقارنة بين حركتين مختلفتين (Test A vs Test B)
class RealInferenceComparisonResult {
  final int argmaxPositionsChanged; // عدد المواقع المتغيرة من 29
  final double maxAbsoluteDifference;
  final double meanAbsoluteDifference;
  final bool outputsIdentical;
  final bool modelRespondsToRealMotion;

  const RealInferenceComparisonResult({
    required this.argmaxPositionsChanged,
    required this.maxAbsoluteDifference,
    required this.meanAbsoluteDifference,
    required this.outputsIdentical,
    required this.modelRespondsToRealMotion,
  });

  /// حساب المقارنة بين نتيجتين
  static RealInferenceComparisonResult compare(
    SingleRealInferenceResult a,
    SingleRealInferenceResult b,
  ) {
    if (!a.isSuccess || !b.isSuccess) {
      return const RealInferenceComparisonResult(
        argmaxPositionsChanged: 0,
        maxAbsoluteDifference: 0.0,
        meanAbsoluteDifference: 0.0,
        outputsIdentical: false,
        modelRespondsToRealMotion: false,
      );
    }

    // 1. حساب المواضع المتغيرة في Argmax (29 timesteps)
    int changedPositions = 0;
    final minLen = math.min(a.rawArgmax.length, b.rawArgmax.length);
    for (int t = 0; t < minLen; t++) {
      if (a.rawArgmax[t] != b.rawArgmax[t]) {
        changedPositions++;
      }
    }
    if (a.rawArgmax.length != b.rawArgmax.length) {
      changedPositions += (a.rawArgmax.length - b.rawArgmax.length).abs();
    }

    // 2. حساب الفروق المطلقة القصوى والمتوسطة (19,836 floats)
    double maxDiff = 0.0;
    double sumDiff = 0.0;
    final totalElements = math.min(a.flatOutput.length, b.flatOutput.length);

    for (int i = 0; i < totalElements; i++) {
      final diff = (a.flatOutput[i] - b.flatOutput[i]).abs();
      if (diff > maxDiff) {
        maxDiff = diff;
      }
      sumDiff += diff;
    }

    final meanDiff = totalElements > 0 ? (sumDiff / totalElements) : 0.0;
    final bool identical = maxDiff < 1e-6;

    // يعتبر الموديل مستجيباً للحركة الحقيقية إذا تغير موقع واحد على الأقل في Argmax
    // أو إذا كانت الفروق في Logits واضحة وملموسة (> 0.01)
    final bool responds =
        !identical && (changedPositions > 0 || maxDiff > 0.01);

    return RealInferenceComparisonResult(
      argmaxPositionsChanged: changedPositions,
      maxAbsoluteDifference: maxDiff,
      meanAbsoluteDifference: meanDiff,
      outputsIdentical: identical,
      modelRespondsToRealMotion: responds,
    );
  }
}

/// جلسة اختبار الاستنتاج الحقيقي الكاملة (Real Inference Session)
class RealInferenceSession {
  final SingleRealInferenceResult? testA;
  final SingleRealInferenceResult? testB;
  final RealInferenceComparisonResult? comparison;
  final int framesSinceTestA; // عداد الإطارات الجديدة منذ Test A (0..128)
  final bool isInferenceRunning;

  const RealInferenceSession({
    this.testA,
    this.testB,
    this.comparison,
    this.framesSinceTestA = 0,
    this.isInferenceRunning = false,
  });

  RealInferenceSession copyWith({
    SingleRealInferenceResult? testA,
    SingleRealInferenceResult? testB,
    RealInferenceComparisonResult? comparison,
    int? framesSinceTestA,
    bool? isInferenceRunning,
    bool clearTestB = false,
  }) {
    return RealInferenceSession(
      testA: testA ?? this.testA,
      testB: clearTestB ? null : (testB ?? this.testB),
      comparison: clearTestB ? null : (comparison ?? this.comparison),
      framesSinceTestA: framesSinceTestA ?? this.framesSinceTestA,
      isInferenceRunning: isInferenceRunning ?? this.isInferenceRunning,
    );
  }

  /// هل تم استيفاء 128 إطاراً جديداً بعد Test A؟
  bool get hasFreshWindowForTestB => framesSinceTestA >= 128;

  /// توليد التقرير النصي الرسمي المطابق تماماً للبند 19
  String toReportText({
    String modelName = 'ishara_model.tflite',
    String modelSize = '107.55 MB',
    String interpreterStatus = 'READY',
  }) {
    final buf = StringBuffer();

    final capturedTime =
        testA?.capturedAt ?? testB?.capturedAt ?? DateTime.now();
    final timeStr = capturedTime
        .toIso8601String()
        .replaceFirst('T', ' ')
        .substring(0, 19);

    buf.writeln('================================');
    buf.writeln('ISHARA REAL INFERENCE REPORT');
    buf.writeln('================================');
    buf.writeln('');
    buf.writeln('Captured At:');
    buf.writeln(timeStr);
    buf.writeln('');
    buf.writeln('Model:');
    buf.writeln(modelName);
    buf.writeln('');
    buf.writeln('Model Size:');
    buf.writeln(modelSize);
    buf.writeln('');
    buf.writeln('Interpreter:');
    buf.writeln(interpreterStatus);
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('REAL INPUT');
    buf.writeln('');

    final refTest = testA ?? testB;
    if (refTest != null) {
      buf.writeln('Buffer:');
      buf.writeln('${refTest.bufferCount}/128');
      buf.writeln('');
      buf.writeln('Input Shape:');
      buf.writeln('[${refTest.inputShape.join(',')}]');
      buf.writeln('');
      buf.writeln('NaN:');
      buf.writeln('${refTest.inputNanCount}');
      buf.writeln('');
      buf.writeln('Infinity:');
      buf.writeln('${refTest.inputInfCount}');
      buf.writeln('');
      buf.writeln('Chronological:');
      buf.writeln(refTest.isChronological ? 'PASS' : 'FAIL');
      buf.writeln('');
      buf.writeln('Sequence Quality:');
      buf.writeln('${refTest.rawKeypointCoveragePct.toStringAsFixed(2)} %');
      buf.writeln('');
      buf.writeln('Imputation:');
      buf.writeln('${refTest.imputationPct.toStringAsFixed(2)} %');
      buf.writeln('');
      buf.writeln('RH Coverage:');
      buf.writeln('${refTest.rightHandCoveragePct.toStringAsFixed(2)} %');
      buf.writeln('');
      buf.writeln('LH Coverage:');
      buf.writeln('${refTest.leftHandCoveragePct.toStringAsFixed(2)} %');
      buf.writeln('');
      buf.writeln('Lips Coverage:');
      buf.writeln('${refTest.lipsCoveragePct.toStringAsFixed(2)} %');
      buf.writeln('');
      buf.writeln('Body Coverage:');
      buf.writeln('${refTest.bodyCoveragePct.toStringAsFixed(2)} %');
    } else {
      buf.writeln('Buffer:');
      buf.writeln('WAITING');
      buf.writeln('');
      buf.writeln('Input Shape:');
      buf.writeln('[1,128,86,2]');
      buf.writeln('');
      buf.writeln('NaN:');
      buf.writeln('0');
      buf.writeln('');
      buf.writeln('Infinity:');
      buf.writeln('0');
      buf.writeln('');
      buf.writeln('Chronological:');
      buf.writeln('WAITING');
      buf.writeln('');
      buf.writeln('Sequence Quality:');
      buf.writeln('WAITING');
    }

    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('TEST A');
    buf.writeln('');

    if (testA != null) {
      buf.writeln('Inference:');
      buf.writeln(testA!.isSuccess ? 'PASS' : 'FAIL');
      buf.writeln('');
      buf.writeln('Inference Time:');
      buf.writeln('${testA!.inferenceTimeMs} ms');
      buf.writeln('');
      buf.writeln('Output Shape:');
      buf.writeln('[${testA!.outputShape.join(',')}]');
      buf.writeln('');
      buf.writeln('Output NaN:');
      buf.writeln('${testA!.outputNanCount}');
      buf.writeln('');
      buf.writeln('Output Infinity:');
      buf.writeln('${testA!.outputInfCount}');
      buf.writeln('');
      buf.writeln('Output Min:');
      buf.writeln(testA!.outputMin.toStringAsFixed(4));
      buf.writeln('');
      buf.writeln('Output Max:');
      buf.writeln(testA!.outputMax.toStringAsFixed(4));
      buf.writeln('');
      buf.writeln('Raw Argmax:');
      buf.writeln('[${testA!.rawArgmax.join(', ')}]');
      buf.writeln('');
      buf.writeln('Unique Classes:');
      buf.writeln('[${testA!.uniqueClasses.join(', ')}]');
      buf.writeln('');
      buf.writeln('Blank Top-1:');
      buf.writeln('${testA!.blankTop1Count} / 29');
    } else {
      buf.writeln('Inference:');
      buf.writeln('WAITING');
    }

    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('TEST B');
    buf.writeln('');

    if (testB != null) {
      buf.writeln('Inference:');
      buf.writeln(testB!.isSuccess ? 'PASS' : 'FAIL');
      buf.writeln('');
      buf.writeln('Inference Time:');
      buf.writeln('${testB!.inferenceTimeMs} ms');
      buf.writeln('');
      buf.writeln('Output Shape:');
      buf.writeln('[${testB!.outputShape.join(',')}]');
      buf.writeln('');
      buf.writeln('Output NaN:');
      buf.writeln('${testB!.outputNanCount}');
      buf.writeln('');
      buf.writeln('Output Infinity:');
      buf.writeln('${testB!.outputInfCount}');
      buf.writeln('');
      buf.writeln('Output Min:');
      buf.writeln(testB!.outputMin.toStringAsFixed(4));
      buf.writeln('');
      buf.writeln('Output Max:');
      buf.writeln(testB!.outputMax.toStringAsFixed(4));
      buf.writeln('');
      buf.writeln('Raw Argmax:');
      buf.writeln('[${testB!.rawArgmax.join(', ')}]');
      buf.writeln('');
      buf.writeln('Unique Classes:');
      buf.writeln('[${testB!.uniqueClasses.join(', ')}]');
      buf.writeln('');
      buf.writeln('Blank Top-1:');
      buf.writeln('${testB!.blankTop1Count} / 29');
    } else {
      buf.writeln('Inference:');
      buf.writeln('WAITING');
    }

    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('A vs B');
    buf.writeln('');

    if (comparison != null) {
      buf.writeln('Argmax Positions Changed:');
      buf.writeln('${comparison!.argmaxPositionsChanged} / 29');
      buf.writeln('');
      buf.writeln('Max Absolute Difference:');
      buf.writeln(comparison!.maxAbsoluteDifference.toStringAsFixed(4));
      buf.writeln('');
      buf.writeln('Mean Absolute Difference:');
      buf.writeln(comparison!.meanAbsoluteDifference.toStringAsFixed(4));
      buf.writeln('');
      buf.writeln('Outputs Identical:');
      buf.writeln(comparison!.outputsIdentical ? 'YES' : 'NO');
      buf.writeln('');
      buf.writeln('MODEL RESPONDS TO REAL MOTION:');
      buf.writeln(comparison!.modelRespondsToRealMotion ? 'YES' : 'NO');
    } else {
      buf.writeln('Argmax Positions Changed:');
      buf.writeln('WAITING');
      buf.writeln('');
      buf.writeln('Outputs Identical:');
      buf.writeln('WAITING');
      buf.writeln('');
      buf.writeln('MODEL RESPONDS TO REAL MOTION:');
      buf.writeln('WAITING');
    }

    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('FINAL RESULT');
    buf.writeln('');

    final bool aOk = testA?.isSuccess ?? false;
    final bool bOk = testB?.isSuccess ?? false;
    final bool compOk = comparison?.modelRespondsToRealMotion ?? false;
    final bool overallPass = aOk && bOk && compOk;

    buf.writeln('REAL PIPELINE:');
    buf.writeln(overallPass ? 'PASS' : ((aOk || bOk) ? 'PARTIAL' : 'WAITING'));
    buf.writeln('');
    buf.writeln('First Failure Point:');
    if (!aOk && testA != null) {
      buf.writeln('TEST A (${testA!.errorCode ?? "UNKNOWN"})');
    } else if (!bOk && testB != null) {
      buf.writeln('TEST B (${testB!.errorCode ?? "UNKNOWN"})');
    } else if (comparison != null && !compOk) {
      buf.writeln('A vs B (NO_MOTION_RESPONSE)');
    } else {
      buf.writeln('None');
    }
    buf.writeln('');
    buf.writeln('Errors:');
    final errors = [
      if (testA?.errorMessage != null) 'Test A: ${testA!.errorMessage}',
      if (testB?.errorMessage != null) 'Test B: ${testB!.errorMessage}',
    ];
    if (errors.isEmpty) {
      buf.writeln('None');
    } else {
      for (final err in errors) {
        buf.writeln(err);
      }
    }
    buf.writeln('');
    buf.writeln('================================');

    return buf.toString();
  }
}
