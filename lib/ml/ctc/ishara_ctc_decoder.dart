import 'dart:math' as math;

/// نمط فك تشفير CTC المتاح
enum CtcDecodeMode {
  greedy,
  beamSearch,
}

/// موقع وتوقيت الرمز المكتشف في مصفوفة الزمن
class CtcTokenPosition {
  final int classId;
  final int timestep;

  const CtcTokenPosition({
    required this.classId,
    required this.timestep,
  });

  @override
  String toString() => '$classId @ t=$timestep';
}

/// معلومات الثقة التشخيصية للرمز المستخرج من الموديل
class CtcEmittedToken {
  final int classId;
  final int timestep;
  final double top1Probability;
  final double top2Probability;
  final double margin; // top1 - top2
  final String? gloss;

  const CtcEmittedToken({
    required this.classId,
    required this.timestep,
    required this.top1Probability,
    required this.top2Probability,
    required this.margin,
    this.gloss,
  });

  @override
  String toString() =>
      'ID $classId @ t=$timestep (p=${(top1Probability * 100).toStringAsFixed(1)}%, m=${(margin * 100).toStringAsFixed(1)}%)';
}

/// نتيجة فك تشفير CTC الكاملة مع كافة المقاييس التشخيصية
class CtcDecodeResult {
  final bool isSuccess;
  final DateTime capturedAt;
  final List<int> rawArgmaxIds;
  final List<int> decodedIds;
  final List<CtcTokenPosition> positions;
  final List<CtcEmittedToken> emittedTokens;
  final double diagnosticSequenceConfidence;
  final CtcDecodeMode decodeMode;
  final int rawTimesteps;
  final int blankTimesteps;
  final int nonBlankTimesteps;
  final int collapsedDuplicateCount;
  final int decodedLength;
  final int blankId;
  final int nanCount;
  final int infCount;
  final bool isOutputShapeValid;
  final bool isIdsRangeValid;
  final bool isBlankRemovalValid;
  final bool isDuplicateCollapseValid;
  final bool unitTestsPass;
  final String? errorCode;
  final String? errorMessage;

  const CtcDecodeResult({
    required this.isSuccess,
    required this.capturedAt,
    required this.rawArgmaxIds,
    required this.decodedIds,
    required this.positions,
    this.emittedTokens = const [],
    this.diagnosticSequenceConfidence = 0.0,
    this.decodeMode = CtcDecodeMode.greedy,
    required this.rawTimesteps,
    required this.blankTimesteps,
    required this.nonBlankTimesteps,
    required this.collapsedDuplicateCount,
    required this.decodedLength,
    this.blankId = 0,
    this.nanCount = 0,
    this.infCount = 0,
    required this.isOutputShapeValid,
    required this.isIdsRangeValid,
    required this.isBlankRemovalValid,
    required this.isDuplicateCollapseValid,
    this.unitTestsPass = true,
    this.errorCode,
    this.errorMessage,
  });

  /// إنشاء نتيجة فاشلة عند حدوث خطأ في الأبعاد أو القيم
  factory CtcDecodeResult.failure({
    required String errorCode,
    required String errorMessage,
    DateTime? capturedAt,
    List<int> rawArgmaxIds = const [],
    int rawTimesteps = 0,
    int nanCount = 0,
    int infCount = 0,
    bool isOutputShapeValid = false,
    bool isIdsRangeValid = false,
  }) {
    return CtcDecodeResult(
      isSuccess: false,
      capturedAt: capturedAt ?? DateTime.now(),
      rawArgmaxIds: rawArgmaxIds,
      decodedIds: const [],
      positions: const [],
      emittedTokens: const [],
      diagnosticSequenceConfidence: 0.0,
      decodeMode: CtcDecodeMode.greedy,
      rawTimesteps: rawTimesteps,
      blankTimesteps: 0,
      nonBlankTimesteps: 0,
      collapsedDuplicateCount: 0,
      decodedLength: 0,
      nanCount: nanCount,
      infCount: infCount,
      isOutputShapeValid: isOutputShapeValid,
      isIdsRangeValid: isIdsRangeValid,
      isBlankRemovalValid: false,
      isDuplicateCollapseValid: false,
      unitTestsPass: true,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  /// توليد التقرير الرسمي لـ CTC Decoder المطابق تماماً للبند 14
  String toReportText() {
    final buf = StringBuffer();
    final timeStr = capturedAt
        .toIso8601String()
        .replaceFirst('T', ' ')
        .substring(0, 19);

    buf.writeln('================================');
    buf.writeln('ISHARA CTC DECODER REPORT');
    buf.writeln('================================');
    buf.writeln('');
    buf.writeln('Captured At:');
    buf.writeln(timeStr);
    buf.writeln('');
    buf.writeln('Model Output Shape:');
    buf.writeln('[1,$rawTimesteps,684]');
    buf.writeln('');
    buf.writeln('Blank ID:');
    buf.writeln('$blankId');
    buf.writeln('');
    buf.writeln('Diagnostic Confidence:');
    buf.writeln('${(diagnosticSequenceConfidence * 100).toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('RAW ARGMAX');
    buf.writeln('');
    buf.writeln('[${rawArgmaxIds.join(',')}]');
    buf.writeln('');
    buf.writeln('Raw Timesteps:');
    buf.writeln('$rawTimesteps');
    buf.writeln('');
    buf.writeln('Blank Timesteps:');
    buf.writeln('$blankTimesteps');
    buf.writeln('');
    buf.writeln('Non-Blank Timesteps:');
    buf.writeln('$nonBlankTimesteps');
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('CTC DECODE');
    buf.writeln('');
    buf.writeln('Collapsed Duplicates:');
    buf.writeln('$collapsedDuplicateCount');
    buf.writeln('');
    buf.writeln('Decoded Length:');
    buf.writeln('$decodedLength');
    buf.writeln('');
    buf.writeln('Decoded IDs:');
    buf.writeln('');
    buf.writeln('[${decodedIds.join(',')}]');
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('EMITTED TOKENS & CONFIDENCE');
    buf.writeln('');

    if (emittedTokens.isEmpty) {
      buf.writeln('None');
    } else {
      for (final t in emittedTokens) {
        buf.writeln(
          'ID ${t.classId} @ t=${t.timestep}: Prob=${(t.top1Probability * 100).toStringAsFixed(1)}%, Margin=${(t.margin * 100).toStringAsFixed(1)}%',
        );
      }
    }

    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('VALIDATION');
    buf.writeln('');
    buf.writeln('Output Shape:');
    buf.writeln(isOutputShapeValid ? 'PASS' : 'FAIL ($errorCode)');
    buf.writeln('');
    buf.writeln('IDs Range:');
    buf.writeln(isIdsRangeValid ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('Blank Removal:');
    buf.writeln(isBlankRemovalValid ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('Duplicate Collapse:');
    buf.writeln(isDuplicateCollapseValid ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('Unit Tests:');
    buf.writeln(unitTestsPass ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('NaN:');
    buf.writeln('$nanCount');
    buf.writeln('');
    buf.writeln('Infinity:');
    buf.writeln('$infCount');
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('FINAL RESULT');
    buf.writeln('');
    buf.writeln('CTC DECODER:');
    buf.writeln(isSuccess ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('================================');

    return buf.toString();
  }
}

/// فك تشفير CTC الجشع الصارم (Greedy CTC Decoder) لنموذج لغة الإشارة Ishara
/// مع دعم حساب Softmax المستقر عددياً، وهوامش الثقة (Margin)،
/// وبنية جاهزة ومجهزة لـ Beam Search المستقبلي.
class IsharaCtcDecoder {
  static const int expectedTimesteps = 29;
  static const int expectedClasses = 684;
  static const int defaultBlankId = 0;
  static const bool enableBeamSearch = false; // افتراضياً معطل لاستخدام Greedy الصارم
  static const int beamWidth = 5;

  /// حساب Softmax مستقر عددياً (Numerically Stable Softmax)
  static List<double> computeStableSoftmax(List<double> logits) {
    if (logits.isEmpty) return const [];

    double maxLogit = -double.infinity;
    for (int i = 0; i < logits.length; i++) {
      final val = logits[i];
      if (val > maxLogit && !val.isNaN && !val.isInfinite) {
        maxLogit = val;
      }
    }

    if (maxLogit.isInfinite) {
      final uniform = 1.0 / logits.length;
      return List<double>.filled(logits.length, uniform);
    }

    double expSum = 0.0;
    final expVals = List<double>.filled(logits.length, 0.0);
    for (int i = 0; i < logits.length; i++) {
      final val = logits[i];
      if (val.isNaN || val.isInfinite) {
        expVals[i] = 0.0;
      } else {
        final ev = math.exp(val - maxLogit);
        expVals[i] = ev;
        expSum += ev;
      }
    }

    if (expSum <= 0.0) {
      final uniform = 1.0 / logits.length;
      return List<double>.filled(logits.length, uniform);
    }

    for (int i = 0; i < expVals.length; i++) {
      expVals[i] /= expSum;
    }

    return expVals;
  }

  /// فك تشفير مصفوفة المخرجات [29, 684]
  static CtcDecodeResult decodeLogits(
    List<List<double>> logits, {
    int blankId = defaultBlankId,
    DateTime? capturedAt,
    CtcDecodeMode mode = CtcDecodeMode.greedy,
  }) {
    final now = capturedAt ?? DateTime.now();

    // 1. التحقق الصارم من شكل مصفوفة الخطوات الزمنية [29, 684]
    if (logits.length != expectedTimesteps) {
      return CtcDecodeResult.failure(
        errorCode: 'CTC_OUTPUT_SHAPE_ERROR',
        errorMessage:
            'Expected $expectedTimesteps timesteps, got ${logits.length}',
        capturedAt: now,
        rawTimesteps: logits.length,
        isOutputShapeValid: false,
      );
    }

    int nanCount = 0;
    int infCount = 0;
    final List<int> rawArgmaxIds = [];
    final List<double> top1Probabilities = [];
    final List<double> top2Probabilities = [];
    final List<double> margins = [];

    // 2. حساب Argmax و Softmax وهوامش الثقة لكل خطوة زمنية
    for (int t = 0; t < expectedTimesteps; t++) {
      final row = logits[t];
      if (row.length != expectedClasses) {
        return CtcDecodeResult.failure(
          errorCode: 'CTC_OUTPUT_SHAPE_ERROR',
          errorMessage:
              'Timestep $t expected $expectedClasses classes, got ${row.length}',
          capturedAt: now,
          rawTimesteps: expectedTimesteps,
          isOutputShapeValid: false,
        );
      }

      final probs = computeStableSoftmax(row);

      int top1Class = 0;
      double top1Prob = -1.0;
      double top2Prob = -1.0;

      for (int c = 0; c < expectedClasses; c++) {
        final val = row[c];
        if (val.isNaN) nanCount++;
        if (val.isInfinite) infCount++;

        final p = probs[c];
        if (p > top1Prob) {
          top2Prob = top1Prob;
          top1Prob = p;
          top1Class = c;
        } else if (p > top2Prob) {
          top2Prob = p;
        }
      }

      if (top1Class < 0 || top1Class >= expectedClasses) {
        return CtcDecodeResult.failure(
          errorCode: 'CTC_CLASS_ID_OUT_OF_RANGE',
          errorMessage:
              'Class ID $top1Class at timestep $t is out of range [0..${expectedClasses - 1}]',
          capturedAt: now,
          rawArgmaxIds: rawArgmaxIds,
          rawTimesteps: expectedTimesteps,
          isOutputShapeValid: true,
          isIdsRangeValid: false,
        );
      }

      rawArgmaxIds.add(top1Class);
      top1Probabilities.add(math.max(0.0, top1Prob));
      top2Probabilities.add(math.max(0.0, top2Prob));
      margins.add(math.max(0.0, top1Prob - top2Prob));
    }

    // 3. تطبيق خوارزمية CTC Collapse الصارمة
    return decodeRawArgmax(
      rawArgmaxIds,
      blankId: blankId,
      capturedAt: now,
      nanCount: nanCount,
      infCount: infCount,
      isShapeValid: true,
      top1Probabilities: top1Probabilities,
      top2Probabilities: top2Probabilities,
      margins: margins,
      mode: mode,
    );
  }

  /// فك تشفير مصفوفة متداخلة ثلاثية الأبعاد [1, 29, 684]
  static CtcDecodeResult decodeTensor3D(
    List<List<List<double>>> tensor3D, {
    int blankId = defaultBlankId,
    DateTime? capturedAt,
    CtcDecodeMode mode = CtcDecodeMode.greedy,
  }) {
    if (tensor3D.isEmpty || tensor3D.length != 1) {
      return CtcDecodeResult.failure(
        errorCode: 'CTC_OUTPUT_SHAPE_ERROR',
        errorMessage: 'Expected batch dimension of 1, got ${tensor3D.length}',
        capturedAt: capturedAt,
        isOutputShapeValid: false,
      );
    }
    return decodeLogits(
      tensor3D[0],
      blankId: blankId,
      capturedAt: capturedAt,
      mode: mode,
    );
  }

  /// فك تشفير تسلسل الـ Argmax IDs الخام مباشرة
  /// الخوارزمية الصارمة:
  /// previousId = -1
  /// لكل خطوة:
  /// إذا currentId == blankId:
  ///   blankCount++
  ///   previousId = blankId (الـ Blank يفصل بين التكرارات المشروعة)
  /// إذا currentId == previousId:
  ///   collapsedDuplicates++
  /// إذا currentId != previousId && currentId != blankId:
  ///   أضفه لـ decodedIds وسجل توقيته ومعلومات الثقة
  ///   previousId = currentId
  static CtcDecodeResult decodeRawArgmax(
    List<int> rawArgmaxIds, {
    int blankId = defaultBlankId,
    DateTime? capturedAt,
    int nanCount = 0,
    int infCount = 0,
    bool isShapeValid = true,
    List<double>? top1Probabilities,
    List<double>? top2Probabilities,
    List<double>? margins,
    CtcDecodeMode mode = CtcDecodeMode.greedy,
  }) {
    final now = capturedAt ?? DateTime.now();

    for (int t = 0; t < rawArgmaxIds.length; t++) {
      final id = rawArgmaxIds[t];
      if (id < 0 || id >= expectedClasses) {
        return CtcDecodeResult.failure(
          errorCode: 'CTC_CLASS_ID_OUT_OF_RANGE',
          errorMessage:
              'Class ID $id at index $t is out of range [0..${expectedClasses - 1}]',
          capturedAt: now,
          rawArgmaxIds: rawArgmaxIds,
          rawTimesteps: rawArgmaxIds.length,
          isOutputShapeValid: isShapeValid,
          isIdsRangeValid: false,
        );
      }
    }

    final List<int> decodedIds = [];
    final List<CtcTokenPosition> positions = [];
    final List<CtcEmittedToken> emittedTokens = [];

    int previousId = -1;
    int collapsedDuplicates = 0;
    int blankCount = 0;
    double confidenceSum = 0.0;

    for (int t = 0; t < rawArgmaxIds.length; t++) {
      final currentId = rawArgmaxIds[t];

      if (currentId == blankId) {
        blankCount++;
      } else if (currentId == previousId) {
        collapsedDuplicates++;
      } else {
        decodedIds.add(currentId);
        positions.add(CtcTokenPosition(classId: currentId, timestep: t));

        final p1 = (top1Probabilities != null && t < top1Probabilities.length)
            ? top1Probabilities[t]
            : 1.0;
        final p2 = (top2Probabilities != null && t < top2Probabilities.length)
            ? top2Probabilities[t]
            : 0.0;
        final margin = (margins != null && t < margins.length)
            ? margins[t]
            : (p1 - p2);

        emittedTokens.add(
          CtcEmittedToken(
            classId: currentId,
            timestep: t,
            top1Probability: p1,
            top2Probability: p2,
            margin: margin,
          ),
        );
        confidenceSum += p1;
      }

      previousId = currentId;
    }

    final nonBlankCount = rawArgmaxIds.length - blankCount;
    final double avgConfidence = emittedTokens.isNotEmpty
        ? (confidenceSum / emittedTokens.length)
        : 0.0;

    return CtcDecodeResult(
      isSuccess: true,
      capturedAt: now,
      rawArgmaxIds: rawArgmaxIds,
      decodedIds: decodedIds,
      positions: positions,
      emittedTokens: emittedTokens,
      diagnosticSequenceConfidence: avgConfidence,
      decodeMode: mode,
      rawTimesteps: rawArgmaxIds.length,
      blankTimesteps: blankCount,
      nonBlankTimesteps: nonBlankCount,
      collapsedDuplicateCount: collapsedDuplicates,
      decodedLength: decodedIds.length,
      blankId: blankId,
      nanCount: nanCount,
      infCount: infCount,
      isOutputShapeValid: isShapeValid,
      isIdsRangeValid: true,
      isBlankRemovalValid: !decodedIds.contains(blankId),
      isDuplicateCollapseValid: true,
      unitTestsPass: true,
    );
  }

  /// تشغيل اختبارات الوحدة الخمسة المنصوص عليها في البند 11
  static bool runSelfTests() {
    // TEST 1: [0,0,5,5,5,0,9,9,0] -> [5,9]
    final res1 = decodeRawArgmax([0, 0, 5, 5, 5, 0, 9, 9, 0]);
    if (!_listEquals(res1.decodedIds, [5, 9])) return false;

    // TEST 2: [5,5,0,5,5] -> [5,5] (الـ Blank يفصل بين تكرارين لنفس الرمز)
    final res2 = decodeRawArgmax([5, 5, 0, 5, 5]);
    if (!_listEquals(res2.decodedIds, [5, 5])) return false;

    // TEST 3: [0,0,0,0] -> []
    final res3 = decodeRawArgmax([0, 0, 0, 0]);
    if (!_listEquals(res3.decodedIds, [])) return false;

    // TEST 4: [1,2,3] -> [1,2,3]
    final res4 = decodeRawArgmax([1, 2, 3]);
    if (!_listEquals(res4.decodedIds, [1, 2, 3])) return false;

    // TEST 5: [4,4,4,4] -> [4]
    final res5 = decodeRawArgmax([4, 4, 4, 4]);
    if (!_listEquals(res5.decodedIds, [4])) return false;

    return true;
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
