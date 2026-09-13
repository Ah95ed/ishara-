import 'dart:math';
import 'package:ishara/services/tflite/ishara_vocab_service.dart';

/// نتيجة فك ترميز CTC لخطوة زمنية أو تسلسل
class DecodedGlossResult {
  final List<int> glossIds;
  final List<String> glosses;
  final List<double> confidences;
  final double averageConfidence;

  const DecodedGlossResult({
    required this.glossIds,
    required this.glosses,
    required this.confidences,
    required this.averageConfidence,
  });

  bool get isEmpty => glosses.isEmpty;
  bool get isNotEmpty => glosses.isNotEmpty;
}

/// مفكك تشفير CTC Greedy مستقل ومطابق تماماً لطريقة فك التشفير في التدريب:
/// 1. Argmax لكل خطوة زمنية (29 خطوة).
/// 2. دمج التكرارات المتتالية (Collapse consecutive duplicates).
/// 3. إزالة CTC Blank (ID = 0).
/// 4. تحويل المعرفات إلى الكلمات العربية (Glosses).
class CtcGreedyDecoder {
  final IsharaVocabService vocabService;
  final int blankId;

  CtcGreedyDecoder({
    required this.vocabService,
    this.blankId = 0,
  });

  /// فك التشفير من مصفوفة الـ Logits الناتجة من الموديل [29, 684]
  DecodedGlossResult decodeLogits(List<List<double>> logits29x684) {
    if (logits29x684.isEmpty) {
      return const DecodedGlossResult(
        glossIds: [],
        glosses: [],
        confidences: [],
        averageConfidence: 0.0,
      );
    }

    // 1. حساب argmax والـ confidence (عبر Softmax) لكل خطوة زمنية
    final rawIds = <int>[];
    final stepConfs = <double>[];

    for (final stepLogits in logits29x684) {
      int bestIdx = 0;
      double maxLogit = stepLogits.isNotEmpty ? stepLogits[0] : double.negativeInfinity;

      for (int i = 1; i < stepLogits.length; i++) {
        if (stepLogits[i] > maxLogit) {
          maxLogit = stepLogits[i];
          bestIdx = i;
        }
      }

      rawIds.add(bestIdx);
      // حساب ثقة الخطوة عبر softmax تقريبي أو max prob
      stepConfs.add(_computeSoftmaxMaxProb(stepLogits, maxLogit));
    }

    return decodeIdsWithConfidence(rawIds, stepConfs);
  }

  /// فك تشفير قائمة المعرفات الخام مع التكرارات
  /// يدمج التكرارات المتتالية ويزيل الـ Blank (ID = 0)
  List<int> decodeRawIds(List<int> rawIds) {
    if (rawIds.isEmpty) return const [];

    final collapsed = <int>[];
    int? prev;

    for (final id in rawIds) {
      if (id != prev) {
        if (id != blankId) {
          collapsed.add(id);
        }
        prev = id;
      }
    }

    return collapsed;
  }

  /// فك تشفير المعرفات وحساب درجات الثقة المقترنة بها
  DecodedGlossResult decodeIdsWithConfidence(List<int> rawIds, List<double> rawConfs) {
    final finalIds = <int>[];
    final finalConfs = <double>[];
    final finalGlosses = <String>[];

    int? prev;
    for (int t = 0; t < rawIds.length; t++) {
      final id = rawIds[t];
      final conf = t < rawConfs.length ? rawConfs[t] : 1.0;

      if (id != prev) {
        if (id != blankId) {
          finalIds.add(id);
          finalConfs.add(conf);
          final gloss = vocabService.getGloss(id);
          if (gloss != null && gloss.isNotEmpty) {
            finalGlosses.add(gloss);
          }
        }
        prev = id;
      }
    }

    final avgConf = finalConfs.isNotEmpty
        ? finalConfs.reduce((a, b) => a + b) / finalConfs.length
        : 0.0;

    return DecodedGlossResult(
      glossIds: finalIds,
      glosses: finalGlosses,
      confidences: finalConfs,
      averageConfidence: avgConf,
    );
  }

  /// حساب احتمال الـ Class الفائز عبر Softmax المستقر عددياً (Numerically stable softmax)
  double _computeSoftmaxMaxProb(List<double> logits, double maxLogit) {
    if (logits.isEmpty) return 0.0;
    double sumExp = 0.0;
    for (int i = 0; i < logits.length; i++) {
      sumExp += exp(logits[i] - maxLogit);
    }
    if (sumExp <= 0.0 || sumExp.isNaN) return 0.0;
    // exp(maxLogit - maxLogit) = 1.0
    return (1.0 / sumExp).clamp(0.0, 1.0);
  }
}
