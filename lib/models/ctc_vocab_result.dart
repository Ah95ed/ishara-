import 'package:ishara/ml/ctc/ishara_ctc_decoder.dart';

/// زوج المعرف والكلمة التوضيحية المقابلة (ID -> Gloss Pair)
class GlossItem {
  final int classId;
  final String gloss;

  const GlossItem({required this.classId, required this.gloss});

  @override
  String toString() => 'ID $classId: Gloss = $gloss';
}

/// نتيجة المعالجة المتكاملة لـ CTC و Vocabulary لنموذج Ishara
/// تمثل الحقيقة الخام المستخرجة من النموذج مع كامل مقاييس الفحص والتحقق.
class CtcVocabResult {
  final String testLabel;
  final DateTime capturedAt;
  final bool isSuccess;

  // ── مقاييس النموذج (Model Metrics) ──
  final List<int> outputShape;
  final int classesCount;
  final int blankId;
  final double sequenceQualityPct;
  final double imputationPct;

  // ── مقاييس CTC (CTC Metrics) ──
  final CtcDecodeResult ctcResult;

  // ── مقاييس القاموس (Vocabulary Metrics) ──
  final String vocabFile;
  final bool isVocabLoaded;
  final int vocabEntries;
  final bool blankHandlingPass;
  final List<int> missingIds;

  // ── الكلمات المتوقعة (Predicted Glosses) ──
  final List<GlossItem> predictedGlosses;
  final List<String> finalGlossSequence;

  // ── الفحوصات والصلاحية (Validation) ──
  final bool ctcUnitTestsPass;
  final bool isOutputShapePass;
  final bool isIdRangePass;
  final bool isVocabMappingPass;
  final int nanCount;
  final int infCount;

  // ── الأخطاء إن وجدت ──
  final String? errorCode;
  final String? errorMessage;

  const CtcVocabResult({
    required this.testLabel,
    required this.capturedAt,
    required this.isSuccess,
    this.outputShape = const [1, 29, 684],
    this.classesCount = 684,
    this.blankId = 0,
    required this.sequenceQualityPct,
    required this.imputationPct,
    required this.ctcResult,
    required this.vocabFile,
    required this.isVocabLoaded,
    required this.vocabEntries,
    required this.blankHandlingPass,
    required this.missingIds,
    required this.predictedGlosses,
    required this.finalGlossSequence,
    required this.ctcUnitTestsPass,
    required this.isOutputShapePass,
    required this.isIdRangePass,
    required this.isVocabMappingPass,
    required this.nanCount,
    required this.infCount,
    this.errorCode,
    this.errorMessage,
  });

  /// إنشاء نتيجة فاشلة عند تعذر وجود استنتاج حقيقي أو حدوث خطأ هيكلي
  factory CtcVocabResult.failure({
    required String testLabel,
    required String errorCode,
    required String errorMessage,
    DateTime? capturedAt,
    String vocabFile = 'assets/models/ishara_vocab.json',
    bool isVocabLoaded = false,
    int vocabEntries = 0,
    double sequenceQualityPct = 0.0,
    double imputationPct = 0.0,
  }) {
    final now = capturedAt ?? DateTime.now();
    return CtcVocabResult(
      testLabel: testLabel,
      capturedAt: now,
      isSuccess: false,
      outputShape: const [1, 29, 684],
      classesCount: 684,
      blankId: 0,
      sequenceQualityPct: sequenceQualityPct,
      imputationPct: imputationPct,
      ctcResult: CtcDecodeResult.failure(
        errorCode: errorCode,
        errorMessage: errorMessage,
        capturedAt: now,
      ),
      vocabFile: vocabFile,
      isVocabLoaded: isVocabLoaded,
      vocabEntries: vocabEntries,
      blankHandlingPass: false,
      missingIds: const [],
      predictedGlosses: const [],
      finalGlossSequence: const [],
      ctcUnitTestsPass: false,
      isOutputShapePass: false,
      isIdRangePass: false,
      isVocabMappingPass: false,
      nanCount: 0,
      infCount: 0,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  /// توليد التقرير النصي المطابق حرفياً لمتطلبات البند 18
  String toReportText() {
    final buf = StringBuffer();
    final timeStr = capturedAt
        .toIso8601String()
        .replaceFirst('T', ' ')
        .substring(0, 19);

    final shapeStr = '[${outputShape.join(',')}]';
    final rawArgmaxStr = '[${ctcResult.rawArgmaxIds.join(',')}]';
    final decodedIdsStr = '[${ctcResult.decodedIds.join(',')}]';

    buf.writeln('================================');
    buf.writeln('ISHARA CTC + VOCAB REPORT');
    buf.writeln('================================');
    buf.writeln('');
    buf.writeln('Captured At:');
    buf.writeln(timeStr);
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('MODEL');
    buf.writeln('');
    buf.writeln('Output Shape:');
    buf.writeln(shapeStr);
    buf.writeln('');
    buf.writeln('Classes:');
    buf.writeln('$classesCount');
    buf.writeln('');
    buf.writeln('Blank ID:');
    buf.writeln('$blankId');
    buf.writeln('');
    buf.writeln('Sequence Quality:');
    buf.writeln('${sequenceQualityPct.toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('Imputation:');
    buf.writeln('${imputationPct.toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('CTC');
    buf.writeln('');
    buf.writeln('Raw Argmax:');
    buf.writeln('');
    buf.writeln(rawArgmaxStr);
    buf.writeln('');
    buf.writeln('Raw Timesteps:');
    buf.writeln('${ctcResult.rawTimesteps}');
    buf.writeln('');
    buf.writeln('Blank Timesteps:');
    buf.writeln('${ctcResult.blankTimesteps} / ${ctcResult.rawTimesteps}');
    buf.writeln('');
    buf.writeln('Non-Blank Timesteps:');
    buf.writeln('${ctcResult.nonBlankTimesteps} / ${ctcResult.rawTimesteps}');
    buf.writeln('');
    buf.writeln('Collapsed Duplicates:');
    buf.writeln('${ctcResult.collapsedDuplicateCount}');
    buf.writeln('');
    buf.writeln('Decoded Length:');
    buf.writeln('${ctcResult.decodedLength}');
    buf.writeln('');
    buf.writeln('Decoded IDs:');
    buf.writeln('');
    buf.writeln(decodedIdsStr);
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('VOCABULARY');
    buf.writeln('');
    buf.writeln('Vocabulary File:');
    buf.writeln(vocabFile);
    buf.writeln('');
    buf.writeln('Vocabulary Loaded:');
    buf.writeln(isVocabLoaded ? 'YES' : 'NO');
    buf.writeln('');
    buf.writeln('Vocabulary Entries:');
    buf.writeln('$vocabEntries');
    buf.writeln('');
    buf.writeln('Blank Handling:');
    buf.writeln(blankHandlingPass ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('Missing IDs:');
    buf.writeln(missingIds.isEmpty ? '[]' : '[${missingIds.join(',')}]');
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('PREDICTED GLOSSES');
    buf.writeln('');

    if (predictedGlosses.isEmpty) {
      buf.writeln('None');
    } else {
      for (int i = 0; i < predictedGlosses.length; i++) {
        final item = predictedGlosses[i];
        buf.writeln('ID ${item.classId}:');
        buf.writeln('Gloss = ${item.gloss}');
        if (i < predictedGlosses.length - 1) {
          buf.writeln('');
        }
      }
    }

    buf.writeln('');
    buf.writeln('Final Gloss Sequence:');
    buf.writeln('');
    buf.writeln('[${finalGlossSequence.join(', ')}]');
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('VALIDATION');
    buf.writeln('');
    buf.writeln('CTC Unit Tests:');
    buf.writeln(ctcUnitTestsPass ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('Output Shape:');
    buf.writeln(isOutputShapePass ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('ID Range:');
    buf.writeln(isIdRangePass ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('Vocabulary Mapping:');
    buf.writeln(isVocabMappingPass ? 'PASS' : 'FAIL');
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
    buf.writeln('CTC:');
    final bool isCtcPass = isOutputShapePass && isIdRangePass && ctcResult.isSuccess;
    buf.writeln(isCtcPass ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('VOCABULARY:');
    final bool isVocabPass = isVocabLoaded && isVocabMappingPass;
    buf.writeln(isVocabPass ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('GLOSS OUTPUT:');
    final bool isGlossAvail = isSuccess && isCtcPass && isVocabPass && finalGlossSequence.isNotEmpty;
    buf.writeln(isGlossAvail ? 'AVAILABLE' : (isSuccess && isCtcPass && isVocabPass ? 'AVAILABLE (Empty Sequence)' : 'NOT AVAILABLE'));
    buf.writeln('');
    buf.writeln('Errors:');
    if (errorCode != null || errorMessage != null) {
      buf.writeln('${errorCode ?? 'ERROR'}: ${errorMessage ?? ''}');
    } else {
      buf.writeln('NONE');
    }
    buf.writeln('');
    buf.writeln('================================');

    return buf.toString();
  }
}
