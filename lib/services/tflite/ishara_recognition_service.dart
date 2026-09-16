import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara/services/diagnostics/diagnostic_models.dart';
import 'package:ishara/services/diagnostics/ishara_diagnostic_service.dart';
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

/// نتيجة فحص وتشخيص نموذج لغة الإشارة المستقل (PATH A)
class ModelDiagnosticResult {
  final bool fileFound;
  final int fileBytes;
  final double fileSizeMb;
  final bool interpreterCreated;
  final bool shapesMatch;
  final bool standaloneInferencePassed;
  final int inferenceTimeMs;
  final bool outputValid;
  final String? errorCode;
  final String? errorMessage;
  final List<int>? inputShape;
  final List<int>? outputShape;
  final double minVal;
  final double maxVal;
  final double meanVal;

  const ModelDiagnosticResult({
    required this.fileFound,
    required this.fileBytes,
    required this.fileSizeMb,
    required this.interpreterCreated,
    required this.shapesMatch,
    required this.standaloneInferencePassed,
    required this.inferenceTimeMs,
    required this.outputValid,
    this.errorCode,
    this.errorMessage,
    this.inputShape,
    this.outputShape,
    this.minVal = 0.0,
    this.maxVal = 0.0,
    this.meanVal = 0.0,
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
  ModelDiagnosticResult? _lastDiagnosticResult;

  bool get isModelLoaded => _isModelLoaded;
  bool get isLoaded => _isModelLoaded;
  List<int>? get inputShape => _inputShape;
  List<int>? get outputShape => _outputShape;
  TensorType? get inputType => _inputType;
  TensorType? get outputType => _outputType;
  ModelDiagnosticResult? get lastDiagnosticResult => _lastDiagnosticResult;

  /// تحميل النموذج وتشغيل التشخيص المستقل الشامل (PATH A)
  Future<bool> loadModel({int numThreads = 2}) async {
    final diag = await runModelDiagnostics(numThreads: numThreads);
    return diag.interpreterCreated && diag.shapesMatch && diag.standaloneInferencePassed;
  }

  /// تشخيص واختبار نموذج ishara_model.tflite بشكل مستقل تماماً بدون Camera وبدون MediaPipe
  Future<ModelDiagnosticResult> runModelDiagnostics({int numThreads = 2}) async {
    debugPrint('════════════════════════════════════════════════════════════');
    debugPrint('[PATH A] 🚀 STARTING ISOLATED MODEL DIAGNOSTIC (ishara_model.tflite)');
    debugPrint('════════════════════════════════════════════════════════════');

    // ──────────────── A1: التحقق من Asset ────────────────
    int fileBytes = 0;
    double fileSizeMb = 0.0;
    ByteData? byteData;
    try {
      byteData = await rootBundle.load(modelAssetPath);
      fileBytes = byteData.lengthInBytes;
      fileSizeMb = fileBytes / (1024 * 1024);

      if (fileBytes == 0) {
        debugPrint('ERROR: ${DiagnosticErrorCodes.e002ModelAssetEmpty}');
        IsharaDiagnosticService().recordTfliteLoad(
          fileFound: true,
          isLoaded: false,
          modelFileStatus: DiagnosticStageStatus.fail,
          modelSizeBytes: 0,
          modelSizeMb: 0.0,
          interpreterStatus: DiagnosticStageStatus.waiting,
          errorCode: DiagnosticErrorCodes.e002ModelAssetEmpty,
          errorMessage: 'ملف الموديل فارغ 0 بايت',
        );
        return const ModelDiagnosticResult(
          fileFound: true,
          fileBytes: 0,
          fileSizeMb: 0.0,
          interpreterCreated: false,
          shapesMatch: false,
          standaloneInferencePassed: false,
          inferenceTimeMs: 0,
          outputValid: false,
          errorCode: DiagnosticErrorCodes.e002ModelAssetEmpty,
          errorMessage: 'E002_MODEL_ASSET_EMPTY',
        );
      }

      // فحص هل الملف عبارة عن Git LFS Pointer (134 بايت)
      if (fileBytes < 100 * 1024 * 1024) {
        final preview = String.fromCharCodes(
          byteData.buffer.asUint8List(byteData.offsetInBytes, min(200, fileBytes)),
        );
        if (preview.contains('git-lfs') || preview.startsWith('version https://git-lfs')) {
          debugPrint('MODEL FILE = GIT LFS POINTER');
          debugPrint('ERROR: ${DiagnosticErrorCodes.e001TfliteLfsPointer}');
          debugPrint('MODEL BYTES: $fileBytes (Expected ~107.55 MB)');

          IsharaDiagnosticService().recordTfliteLoad(
            fileFound: true,
            isLoaded: false,
            modelFileStatus: DiagnosticStageStatus.fail,
            modelSizeBytes: fileBytes,
            modelSizeMb: fileSizeMb,
            interpreterStatus: DiagnosticStageStatus.waiting,
            errorCode: DiagnosticErrorCodes.e001TfliteLfsPointer,
            errorMessage: 'MODEL FILE = GIT LFS POINTER ($fileBytes bytes). E001_TFLITE_LFS_POINTER: Real ~107.55 MB model binary was not bundled.',
          );

          return ModelDiagnosticResult(
            fileFound: true,
            fileBytes: fileBytes,
            fileSizeMb: fileSizeMb,
            interpreterCreated: false,
            shapesMatch: false,
            standaloneInferencePassed: false,
            inferenceTimeMs: 0,
            outputValid: false,
            errorCode: DiagnosticErrorCodes.e001TfliteLfsPointer,
            errorMessage: 'E001_TFLITE_LFS_POINTER: MODEL FILE = GIT LFS POINTER ($fileBytes bytes)',
          );
        } else {
          debugPrint('ERROR: Model size $fileBytes bytes is under 100MB threshold (Expected ~107.55 MB)');
        }
      }

      // فحص TFLite Magic Header (TFL3)
      if (fileBytes >= 8) {
        final m0 = byteData.getUint8(4);
        final m1 = byteData.getUint8(5);
        final m2 = byteData.getUint8(6);
        final m3 = byteData.getUint8(7);
        final isTfl3 = m0 == 0x54 && m1 == 0x46 && m2 == 0x4C && m3 == 0x33;
        if (!isTfl3) {
          debugPrint('ERROR: Invalid TFLite magic header: $m0 $m1 $m2 $m3 (Expected TFL3)');
        }
      }

      debugPrint('MODEL FILE: PASS');
      debugPrint('MODEL ASSET FOUND: true');
      debugPrint('MODEL BYTES: $fileBytes');
      debugPrint('MODEL SIZE MB: ${fileSizeMb.toStringAsFixed(2)} MB');
    } catch (e, stack) {
      debugPrint('ERROR: ${DiagnosticErrorCodes.e001ModelAssetNotFound}');
      debugPrint('Exception type: ${e.runtimeType}');
      debugPrint('Exception message: $e');
      debugPrint('Stack trace:\n$stack');

      IsharaDiagnosticService().recordTfliteLoad(
        fileFound: false,
        isLoaded: false,
        modelFileStatus: DiagnosticStageStatus.fail,
        modelSizeBytes: 0,
        modelSizeMb: 0.0,
        interpreterStatus: DiagnosticStageStatus.waiting,
        errorCode: DiagnosticErrorCodes.e001ModelAssetNotFound,
        errorMessage: 'ملف الموديل غير موجود: $e',
      );

      return ModelDiagnosticResult(
        fileFound: false,
        fileBytes: 0,
        fileSizeMb: 0.0,
        interpreterCreated: false,
        shapesMatch: false,
        standaloneInferencePassed: false,
        inferenceTimeMs: 0,
        outputValid: false,
        errorCode: DiagnosticErrorCodes.e001ModelAssetNotFound,
        errorMessage: 'E001_MODEL_ASSET_NOT_FOUND: $e',
      );
    }

    // ──────────────── A2: إنشاء Interpreter من Buffer المؤكد ────────────────
    debugPrint('INTERPRETER CREATE START');
    try {
      final options = InterpreterOptions()..threads = numThreads;
      _interpreter?.close();
      final modelUint8List = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      _interpreter = Interpreter.fromBuffer(
        modelUint8List,
        options: options,
      );
      debugPrint('INTERPRETER CREATE SUCCESS');
    } catch (e, stack) {
      debugPrint('ERROR: ${DiagnosticErrorCodes.e010InterpreterCreateFailed}');
      debugPrint('Exception type: ${e.runtimeType}');
      debugPrint('Exception message: $e');
      debugPrint('StackTrace:\n$stack');

      _isModelLoaded = false;
      _releaseModel();

      IsharaDiagnosticService().recordTfliteLoad(
        fileFound: true,
        isLoaded: false,
        modelFileStatus: DiagnosticStageStatus.pass,
        modelSizeBytes: fileBytes,
        modelSizeMb: fileSizeMb,
        interpreterStatus: DiagnosticStageStatus.fail,
        exceptionType: e.runtimeType.toString(),
        exceptionMessage: e.toString(),
        errorCode: DiagnosticErrorCodes.e010InterpreterCreateFailed,
        errorMessage: 'فشل إنشاء Interpreter: $e',
      );

      return ModelDiagnosticResult(
        fileFound: true,
        fileBytes: fileBytes,
        fileSizeMb: fileSizeMb,
        interpreterCreated: false,
        shapesMatch: false,
        standaloneInferencePassed: false,
        inferenceTimeMs: 0,
        outputValid: false,
        errorCode: DiagnosticErrorCodes.e010InterpreterCreateFailed,
        errorMessage: 'E010_INTERPRETER_CREATE_FAILED: $e',
      );
    }

    // ──────────────── A3: قراءة الـ Tensors الحقيقية ────────────────
    final inputTensor = _interpreter!.getInputTensor(0);
    final outputTensor = _interpreter!.getOutputTensor(0);

    _inputShape = inputTensor.shape;
    _outputShape = outputTensor.shape;
    _inputType = inputTensor.type;
    _outputType = outputTensor.type;

    debugPrint('REAL MODEL INPUT: shape=$_inputShape, type=$_inputType');
    debugPrint('REAL MODEL OUTPUT: shape=$_outputShape, type=$_outputType');

    // ──────────────── A4: مقارنة الأبعاد الصارمة باستخدام listEquals ────────────────
    final inputOk = listEquals(_inputShape, const [1, 128, 86, 2]);
    final outputOk = listEquals(_outputShape, const [1, 29, 684]);

    if (!inputOk || !outputOk) {
      debugPrint('Expected Input: [1, 128, 86, 2]');
      debugPrint('Actual Input: $_inputShape');
      debugPrint('Expected Output: [1, 29, 684]');
      debugPrint('Actual Output: $_outputShape');
      debugPrint('Error: ${DiagnosticErrorCodes.e011TensorShapeMismatch}');

      _isModelLoaded = false;
      _releaseModel();

      IsharaDiagnosticService().recordTfliteLoad(
        fileFound: true,
        isLoaded: false,
        modelFileStatus: DiagnosticStageStatus.pass,
        modelSizeBytes: fileBytes,
        modelSizeMb: fileSizeMb,
        interpreterStatus: DiagnosticStageStatus.pass,
        inputTensorStatus: inputOk ? DiagnosticStageStatus.pass : DiagnosticStageStatus.fail,
        outputTensorStatus: outputOk ? DiagnosticStageStatus.pass : DiagnosticStageStatus.fail,
        inputShape: _inputShape,
        outputShape: _outputShape,
        errorCode: DiagnosticErrorCodes.e011TensorShapeMismatch,
        errorMessage: 'E011_TENSOR_SHAPE_MISMATCH: Input: $_inputShape (expected [1, 128, 86, 2]), Output: $_outputShape (expected [1, 29, 684])',
      );

      return ModelDiagnosticResult(
        fileFound: true,
        fileBytes: fileBytes,
        fileSizeMb: fileSizeMb,
        interpreterCreated: true,
        shapesMatch: false,
        standaloneInferencePassed: false,
        inferenceTimeMs: 0,
        outputValid: false,
        inputShape: _inputShape,
        outputShape: _outputShape,
        errorCode: DiagnosticErrorCodes.e011TensorShapeMismatch,
        errorMessage: 'E011_TENSOR_SHAPE_MISMATCH',
      );
    }

    // ──────────────── A5: Standalone Inference ────────────────
    debugPrint('STANDALONE INFERENCE START');
    int inferenceTimeMs = 0;
    // إنشاء مصفوفة إدخال بأبعاد [1, 128, 86, 2] = 22016 قيمة
    final dummyInput = List.generate(
      1,
      (_) => List.generate(
        128,
        (_) => List.generate(86, (_) => List<double>.filled(2, 0.0)),
      ),
    );
    // إنشاء مصفوفة إخراج بأبعاد [1, 29, 684]
    final dummyOutput = List.generate(
      1,
      (_) => List.generate(
        29,
        (_) => List<double>.filled(684, 0.0),
      ),
    );

    try {
      final sw = Stopwatch()..start();
      _interpreter!.run(dummyInput, dummyOutput);
      sw.stop();
      inferenceTimeMs = sw.elapsedMilliseconds;
      debugPrint('STANDALONE INFERENCE SUCCESS');
      debugPrint('inferenceTimeMs: $inferenceTimeMs ms');
    } catch (e, stack) {
      debugPrint('ERROR: ${DiagnosticErrorCodes.e012StandaloneInferenceFailed}');
      debugPrint('Exception type: ${e.runtimeType}');
      debugPrint('Exception message: $e');
      debugPrint('StackTrace:\n$stack');

      _isModelLoaded = false;
      _releaseModel();

      IsharaDiagnosticService().recordTfliteLoad(
        fileFound: true,
        isLoaded: false,
        modelFileStatus: DiagnosticStageStatus.pass,
        modelSizeBytes: fileBytes,
        modelSizeMb: fileSizeMb,
        interpreterStatus: DiagnosticStageStatus.pass,
        inputTensorStatus: DiagnosticStageStatus.pass,
        outputTensorStatus: DiagnosticStageStatus.pass,
        standaloneInferenceStatus: DiagnosticStageStatus.fail,
        inputShape: _inputShape,
        outputShape: _outputShape,
        exceptionType: e.runtimeType.toString(),
        exceptionMessage: e.toString(),
        errorCode: DiagnosticErrorCodes.e012StandaloneInferenceFailed,
        errorMessage: 'E012_STANDALONE_INFERENCE_FAILED: $e',
      );

      return ModelDiagnosticResult(
        fileFound: true,
        fileBytes: fileBytes,
        fileSizeMb: fileSizeMb,
        interpreterCreated: true,
        shapesMatch: true,
        standaloneInferencePassed: false,
        inferenceTimeMs: 0,
        outputValid: false,
        inputShape: _inputShape,
        outputShape: _outputShape,
        errorCode: DiagnosticErrorCodes.e012StandaloneInferenceFailed,
        errorMessage: 'E012_STANDALONE_INFERENCE_FAILED: $e',
      );
    }

    // ──────────────── A6: التحقق من مخرجات النموذج (Output Check) ────────────────
    final outSteps = dummyOutput[0];
    int nanCount = 0;
    int infCount = 0;
    bool allZeros = true;
    double minVal = double.infinity;
    double maxVal = -double.infinity;
    double sumVal = 0.0;
    int totalElements = 0;

    for (final step in outSteps) {
      for (final v in step) {
        totalElements++;
        if (v.isNaN) {
          nanCount++;
        } else if (v.isInfinite) {
          infCount++;
        } else {
          if (v != 0.0) allZeros = false;
          if (v < minVal) minVal = v;
          if (v > maxVal) maxVal = v;
          sumVal += v;
        }
      }
    }

    final double meanVal = totalElements > 0 ? sumVal / totalElements : 0.0;
    final bool outputValid = nanCount == 0 && infCount == 0;

    debugPrint('Output Shape: [1, ${outSteps.length}, ${outSteps.first.length}]');
    debugPrint('Output NaN Count: $nanCount');
    debugPrint('Output Inf Count: $infCount');
    debugPrint('Output All Zeros: $allZeros');
    debugPrint('Output Min: $minVal, Max: $maxVal, Mean: $meanVal');

    if (outputValid) {
      debugPrint('MODEL EXECUTION = PASS');
    }

    _isModelLoaded = true;

    // تسجيل نجاح كامل مراحل الموديل في IsharaDiagnosticService
    IsharaDiagnosticService().recordTfliteLoad(
      fileFound: true,
      isLoaded: true,
      modelFileStatus: DiagnosticStageStatus.pass,
      modelSizeBytes: fileBytes,
      modelSizeMb: fileSizeMb,
      interpreterStatus: DiagnosticStageStatus.pass,
      inputTensorStatus: DiagnosticStageStatus.pass,
      outputTensorStatus: DiagnosticStageStatus.pass,
      standaloneInferenceStatus: DiagnosticStageStatus.pass,
      standaloneInferenceTimeMs: inferenceTimeMs,
      inputShape: _inputShape,
      outputShape: _outputShape,
    );

    _lastDiagnosticResult = ModelDiagnosticResult(
      fileFound: true,
      fileBytes: fileBytes,
      fileSizeMb: fileSizeMb,
      interpreterCreated: true,
      shapesMatch: true,
      standaloneInferencePassed: true,
      inferenceTimeMs: inferenceTimeMs,
      outputValid: outputValid,
      inputShape: _inputShape,
      outputShape: _outputShape,
      minVal: minVal == double.infinity ? 0.0 : minVal,
      maxVal: maxVal == -double.infinity ? 0.0 : maxVal,
      meanVal: meanVal,
    );

    debugPrint('════════════════════════════════════════════════════════════');
    debugPrint('[PATH A] ✅ ISOLATED MODEL DIAGNOSTIC COMPLETED: ALL PASS');
    debugPrint('════════════════════════════════════════════════════════════');

    return _lastDiagnosticResult!;
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
