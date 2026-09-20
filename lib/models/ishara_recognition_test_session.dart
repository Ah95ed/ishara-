/// حالات جلسة الاختبار البسيطة
enum RecognitionTestState {
  idle, // الحالة: جاهز
  collecting, // جاري الالتقاط... 84 / 128
  processing, // جاري التحليل...
  result, // النتيجة: بنت - اخ - صغير
  failed, // لم تكتمل البيانات، أعد المحاولة
}

extension RecognitionTestStateExt on RecognitionTestState {
  String get nameUpper {
    switch (this) {
      case RecognitionTestState.idle:
        return 'IDLE';
      case RecognitionTestState.collecting:
        return 'COLLECTING';
      case RecognitionTestState.processing:
        return 'PROCESSING';
      case RecognitionTestState.result:
        return 'RESULT';
      case RecognitionTestState.failed:
        return 'FAILED';
    }
  }

  bool get isIdle => this == RecognitionTestState.idle;
  bool get isCollecting => this == RecognitionTestState.collecting;
  bool get isProcessing => this == RecognitionTestState.processing;
  bool get isResult => this == RecognitionTestState.result;
  bool get isFailed => this == RecognitionTestState.failed;
}

/// IsharaRecognitionTestSession
/// نموذج جلسة الاختبار المستقلة لـ Ishara:
/// - يبدأ العداد من لحظة الضغط على [ ابدأ الاختبار ]
/// - يجمع 128 إطاراً جديدة فقط
/// - ينتهي إما عند 128 إطاراً أو عند 15 ثانية كحد أقصى للأمان
/// - يولد التقرير التشخيصي النصي المخصص للحافظة (Clipboard Report)
class IsharaRecognitionTestSession {
  final DateTime capturedAt;
  final int collectedFrames;
  final int targetFrames;
  final int durationMs;
  final double sequenceQualityPct;
  final double imputationPct;
  final double rhCoveragePct;
  final double lhCoveragePct;
  final double lipsCoveragePct;
  final double bodyCoveragePct;
  final List<int> inputShape;
  final List<int> outputShape;
  final bool inferencePass;
  final int inferenceTimeMs;
  final List<int> rawArgmaxIds;
  final List<int> ctcIds;
  final List<String> glosses;
  final String finalResultDisplay;
  final bool signStartDetected;
  final bool signEndDetected;
  final String endReason;
  final String errors;

  const IsharaRecognitionTestSession({
    required this.capturedAt,
    required this.collectedFrames,
    this.targetFrames = 128,
    required this.durationMs,
    required this.sequenceQualityPct,
    required this.imputationPct,
    required this.rhCoveragePct,
    required this.lhCoveragePct,
    required this.lipsCoveragePct,
    required this.bodyCoveragePct,
    this.inputShape = const [1, 128, 86, 2],
    this.outputShape = const [1, 29, 684],
    required this.inferencePass,
    required this.inferenceTimeMs,
    required this.rawArgmaxIds,
    required this.ctcIds,
    required this.glosses,
    required this.finalResultDisplay,
    required this.signStartDetected,
    required this.signEndDetected,
    required this.endReason,
    this.errors = 'NONE',
  });

  /// إنشاء جلسة فاشلة (مثل انتهاء الـ Timeout)
  factory IsharaRecognitionTestSession.failed({
    required int collectedFrames,
    required int durationMs,
    String reason = 'TIMEOUT',
    String errorMessage = 'لم تكتمل البيانات، أعد المحاولة',
  }) {
    return IsharaRecognitionTestSession(
      capturedAt: DateTime.now(),
      collectedFrames: collectedFrames,
      durationMs: durationMs,
      sequenceQualityPct: 0.0,
      imputationPct: 0.0,
      rhCoveragePct: 0.0,
      lhCoveragePct: 0.0,
      lipsCoveragePct: 0.0,
      bodyCoveragePct: 0.0,
      inferencePass: false,
      inferenceTimeMs: 0,
      rawArgmaxIds: const [],
      ctcIds: const [],
      glosses: const [],
      finalResultDisplay: errorMessage,
      signStartDetected: false,
      signEndDetected: false,
      endReason: reason,
      errors: errorMessage,
    );
  }

  /// توليد التقرير النصي المطابق حرفياً لمتطلبات البند 18
  String toClipboardReportText() {
    final buf = StringBuffer();
    final timeStr = capturedAt
        .toIso8601String()
        .replaceFirst('T', ' ')
        .substring(0, 19);

    final String resultLine = glosses.isNotEmpty
        ? glosses.join(' | ')
        : (finalResultDisplay.isNotEmpty ? finalResultDisplay : 'NONE');

    buf.writeln('================================');
    buf.writeln('ISHARA SIMPLE TEST RESULT');
    buf.writeln('================================');
    buf.writeln('');
    buf.writeln('Captured At:');
    buf.writeln(timeStr);
    buf.writeln('');
    buf.writeln('Frames:');
    buf.writeln('$collectedFrames/$targetFrames');
    buf.writeln('');
    buf.writeln('Duration:');
    buf.writeln('$durationMs ms');
    buf.writeln('');
    buf.writeln('Sequence Quality:');
    buf.writeln('${sequenceQualityPct.toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('Imputation:');
    buf.writeln('${imputationPct.toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('RH:');
    buf.writeln('${rhCoveragePct.toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('LH:');
    buf.writeln('${lhCoveragePct.toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('Lips:');
    buf.writeln('${lipsCoveragePct.toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('Body:');
    buf.writeln('${bodyCoveragePct.toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('Input:');
    buf.writeln('[${inputShape.join(',')}]');
    buf.writeln('');
    buf.writeln('Output:');
    buf.writeln('[${outputShape.join(',')}]');
    buf.writeln('');
    buf.writeln('Inference:');
    buf.writeln(inferencePass ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('Inference Time:');
    buf.writeln('$inferenceTimeMs ms');
    buf.writeln('');
    buf.writeln('CTC IDs:');
    buf.writeln('[${ctcIds.join(',')}]');
    buf.writeln('');
    buf.writeln('Glosses:');
    buf.writeln('[${glosses.join(', ')}]');
    buf.writeln('');
    buf.writeln('Final Result:');
    buf.writeln(resultLine);
    buf.writeln('');
    buf.writeln('Sign Start:');
    buf.writeln(signStartDetected ? 'YES' : 'NO');
    buf.writeln('');
    buf.writeln('Sign End:');
    buf.writeln(signEndDetected ? 'YES' : 'NO');
    buf.writeln('');
    buf.writeln('End Reason:');
    buf.writeln(endReason);
    buf.writeln('');
    buf.writeln('Errors:');
    buf.writeln(errors);
    buf.writeln('');
    buf.writeln('================================');

    return buf.toString();
  }
}
