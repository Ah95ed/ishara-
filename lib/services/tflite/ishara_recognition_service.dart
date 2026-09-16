import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:ishara/services/tflite/ishara_vocab_service.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// عنصر تصنيف خام مع المعرف والـ Gloss والدرجة
class RawClassEntry {
  final int classId;
  final String gloss;
  final double score;

  const RawClassEntry({
    required this.classId,
    required this.gloss,
    required this.score,
  });

  @override
  String toString() =>
      'ID: $classId | Gloss: $gloss | Score: ${(score * 100).toStringAsFixed(1)}%';
}

/// نتيجة تحليل الاستنتاج الخام
class ModelInferenceAnalysis {
  final List<List<double>> logits;
  final List<List<double>> probabilities;
  final List<RawClassEntry> top10Classes;
  final double blankRatio;
  final double top1Margin;
  final double sequenceConfidence;
  final bool isBlankDominant;

  const ModelInferenceAnalysis({
    required this.logits,
    required this.probabilities,
    required this.top10Classes,
    required this.blankRatio,
    required this.top1Margin,
    required this.sequenceConfidence,
    required this.isBlankDominant,
  });
}

/// خدمة مستقلة لتشغيل نموذج لغة الإشارة العربية CSLR Transformer (ishara_model.tflite)
/// محلياً بالكامل على Android عبر TFLite/LiteRT.
class IsharaRecognitionService {
  static const String modelAssetPath = 'assets/models/ishara_model.tflite';
  static const List<int> expectedInputShape = [1, 128, 86, 2];
  static const List<int> expectedOutputShape = [1, 29, 684];

  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  List<int>? _inputShape;
  List<int>? _outputShape;
  TensorType? _inputType;
  TensorType? _outputType;

  bool get isModelLoaded => _isModelLoaded;
  List<int>? get inputShape => _inputShape;
  List<int>? get outputShape => _outputShape;
  TensorType? get inputType => _inputType;
  TensorType? get outputType => _outputType;

  /// تحميل النموذج والتحقق الصارم من صحة الأبعاد ونوع البيانات
  Future<bool> loadModel({int numThreads = 2}) async {
    if (_isModelLoaded && _interpreter != null) {
      return true;
    }

    try {
      final options = InterpreterOptions()..threads = numThreads;
      _interpreter = await Interpreter.fromAsset(
        modelAssetPath,
        options: options,
      );

      final inputTensor = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);

      _inputShape = inputTensor.shape;
      _outputShape = outputTensor.shape;
      _inputType = inputTensor.type;
      _outputType = outputTensor.type;

      debugPrint('==================================================');
      debugPrint('[IsharaRecognitionService] Model loaded successfully');
      debugPrint('Input shape: $_inputShape');
      debugPrint('Output shape: $_outputShape');
      debugPrint('Input type: $_inputType');
      debugPrint('Output type: $_outputType');
      debugPrint('==================================================');

      final inputOk = listEquals(_inputShape, expectedInputShape);
      final outputOk = listEquals(_outputShape, expectedOutputShape);

      if (!inputOk || !outputOk) {
        final buffer = StringBuffer();
        buffer.writeln('TFLite model validation failed.');
        buffer.writeln('Expected input: ${expectedInputShape.toList()}');
        buffer.writeln('Actual input: ${_inputShape?.toList() ?? 'null'}');
        buffer.writeln('Expected output: ${expectedOutputShape.toList()}');
        buffer.writeln('Actual output: ${_outputShape?.toList() ?? 'null'}');

        final errorMsg = buffer.toString();
        debugPrint('[IsharaRecognitionService] ❌ $errorMsg');
        _releaseModel();
        throw StateError(errorMsg);
      }

      _isModelLoaded = true;
      return true;
    } catch (e, stack) {
      _isModelLoaded = false;
      _releaseModel();
      debugPrint(
        '[IsharaRecognitionService] ❌ Failed to load model: $e\n$stack',
      );
      return false;
    }
  }

  /// تشغيل الاستنتاج على مصفوفة الإدخال [1, 128, 86, 2]
  /// وإعادة مصفوفة الـ Logits بأبعاد [29, 684]
  List<List<double>>? runInference(List<List<List<double>>> frames128x86x2) {
    if (!_isModelLoaded || _interpreter == null) {
      debugPrint(
        '[IsharaRecognitionService] Cannot run inference: Model not loaded',
      );
      return null;
    }

    if (frames128x86x2.length != 128) {
      debugPrint(
        '[IsharaRecognitionService] Invalid frames length: ${frames128x86x2.length} (expected 128)',
      );
      return null;
    }

    try {
      final input = [frames128x86x2];
      final output = List.generate(
        1,
        (_) => List.generate(29, (_) => List<double>.filled(684, 0.0)),
      );

      _interpreter!.run(input, output);
      return output[0];
    } catch (e, stack) {
      debugPrint('[IsharaRecognitionService] ❌ Inference error: $e\n$stack');
      return null;
    }
  }

  /// تحليل مفصل للـ Logits: تطبيق Softmax المستقر عددياً، حساب الـ Blank Ratio،
  /// واستخراج وطباعة الـ Top-10 Classes الخام (المتطلب 17، 18، 20)
  ModelInferenceAnalysis analyzeLogits(
    List<List<double>> logits29x684, {
    IsharaVocabService? vocabService,
  }) {
    final probs29x684 = computeSoftmaxMatrix(logits29x684);

    // 1. تجميع أعلى الاحتمالات لكل فئة عبر الخطوات الزمنية الـ 29
    final maxClassScores = List<double>.filled(684, 0.0);
    int blankTopCount = 0;
    final nonBlankMaxProbs = <double>[];

    for (int t = 0; t < probs29x684.length; t++) {
      final stepProbs = probs29x684[t];
      int bestIdx = 0;
      double bestProb = stepProbs[0];

      for (int c = 1; c < stepProbs.length; c++) {
        if (stepProbs[c] > bestProb) {
          bestProb = stepProbs[c];
          bestIdx = c;
        }
      }

      if (bestIdx == 0) {
        blankTopCount++;
      } else {
        nonBlankMaxProbs.add(bestProb);
      }

      for (int c = 0; c < stepProbs.length; c++) {
        if (stepProbs[c] > maxClassScores[c]) {
          maxClassScores[c] = stepProbs[c];
        }
      }
    }

    final double blankRatio = probs29x684.isNotEmpty
        ? blankTopCount / probs29x684.length
        : 1.0;

    final double sequenceConfidence = nonBlankMaxProbs.isNotEmpty
        ? nonBlankMaxProbs.reduce((a, b) => a + b) / nonBlankMaxProbs.length
        : 0.0;

    // 2. استخراج الـ Top-10 فئات غير الفارغة (Non-blank classes)
    final entries = <RawClassEntry>[];
    for (int c = 1; c < 684; c++) {
      final score = maxClassScores[c];
      if (score > 1e-5) {
        final gloss = vocabService?.getGloss(c) ?? 'Class_$c';
        entries.add(RawClassEntry(classId: c, gloss: gloss, score: score));
      }
    }

    entries.sort((a, b) => b.score.compareTo(a.score));
    final top10 = entries.take(10).toList();

    // 3. حساب هامش الفارق بين أعلى تصنيفين
    double top1Margin = 0.0;
    if (top10.length >= 2) {
      top1Margin = top10[0].score - top10[1].score;
    } else if (top10.length == 1) {
      top1Margin = top10[0].score;
    }

    // 4. طباعة الـ Top-10 الخام في Debug (المتطلب 17)
    if (kDebugMode && top10.isNotEmpty) {
      debugPrint('────────── [RAW TOP-10 TFLITE INFERENCE CLASSES] ──────────');
      for (int i = 0; i < top10.length; i++) {
        final e = top10[i];
        debugPrint(
          '  Top ${i + 1}: ID ${e.classId} | Gloss: "${e.gloss}" | Score: ${(e.score * 100).toStringAsFixed(2)}%',
        );
      }
      debugPrint(
        '  Blank Ratio: ${(blankRatio * 100).toStringAsFixed(1)}% | Sequence Conf: ${(sequenceConfidence * 100).toStringAsFixed(1)}% | Top1/Top2 Margin: ${(top1Margin * 100).toStringAsFixed(2)}%',
      );
      debugPrint(
        '─────────────────────────────────────────────────────────────',
      );
    }

    return ModelInferenceAnalysis(
      logits: logits29x684,
      probabilities: probs29x684,
      top10Classes: top10,
      blankRatio: blankRatio,
      top1Margin: top1Margin,
      sequenceConfidence: sequenceConfidence,
      isBlankDominant: blankRatio > 0.82,
    );
  }

  /// حساب Softmax المستقر عددياً لمصفوفة [29, 684]
  static List<List<double>> computeSoftmaxMatrix(List<List<double>> logits) {
    final result = <List<double>>[];
    for (final stepLogits in logits) {
      result.add(computeSoftmaxVector(stepLogits));
    }
    return result;
  }

  /// حساب Softmax المستقر عددياً لشعاع احتمالات
  static List<double> computeSoftmaxVector(List<double> vector) {
    if (vector.isEmpty) return [];

    double maxVal = vector[0];
    for (int i = 1; i < vector.length; i++) {
      if (vector[i] > maxVal) maxVal = vector[i];
    }

    double sumExp = 0.0;
    final exps = List<double>.filled(vector.length, 0.0);
    for (int i = 0; i < vector.length; i++) {
      final ev = exp(vector[i] - maxVal);
      exps[i] = ev;
      sumExp += ev;
    }

    if (sumExp <= 0.0 || sumExp.isNaN) {
      return List<double>.filled(vector.length, 1.0 / vector.length);
    }

    final probs = List<double>.filled(vector.length, 0.0);
    for (int i = 0; i < vector.length; i++) {
      probs[i] = exps[i] / sumExp;
    }
    return probs;
  }

  void _releaseModel() {
    try {
      _interpreter?.close();
    } catch (_) {}
    _interpreter = null;
    _isModelLoaded = false;
  }

  void dispose() {
    _releaseModel();
  }
}
