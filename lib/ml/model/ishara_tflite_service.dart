import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara/ml/buffer/ishara_frame_ring_buffer.dart';
import 'package:ishara/ml/model/ishara_model_validator.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// حالات تحميل وتشغيل الموديل
enum ModelLoadState {
  notLoaded,
  loading,
  ready,
  error,
}

extension ModelLoadStateExt on ModelLoadState {
  String get displayName {
    switch (this) {
      case ModelLoadState.notLoaded:
        return 'NOT_LOADED';
      case ModelLoadState.loading:
        return 'LOADING';
      case ModelLoadState.ready:
        return 'READY';
      case ModelLoadState.error:
        return 'ERROR';
    }
  }
}

/// نتيجة تنفيذ الاستنتاج (Inference Execution Result)
class InferenceResult {
  final bool isSuccess;
  final int inferenceTimeMs;
  final List<int> inputShape; // [1, 128, 86, 2]
  final List<int> outputShape; // [1, 29, 684]
  final List<int> argmaxIds; // 29 integers
  final List<TimestepLogitDiagnostic> topLogits;
  final bool isResponsive; // هل تغيرت المخرجات مقارنة بالإشارة السابقة
  final int nanCount;
  final int infCount;
  final String? errorCode;
  final String? errorMessage;

  const InferenceResult({
    required this.isSuccess,
    required this.inferenceTimeMs,
    required this.inputShape,
    required this.outputShape,
    required this.argmaxIds,
    required this.topLogits,
    required this.isResponsive,
    required this.nanCount,
    required this.infCount,
    this.errorCode,
    this.errorMessage,
  });
}

/// مخرجات الاستنتاج الحقيقي الخام [1, 29, 684] مع الإحصائيات الكاملة
class RawRealInferenceOutput {
  final bool isSuccess;
  final int inferenceTimeMs;
  final List<int> outputShape; // [1, 29, 684]
  final int nanCount;
  final int infCount;
  final double outputMin;
  final double outputMax;
  final double outputMean;
  final double outputStdDev;
  final List<int> rawArgmax; // 29 integers
  final List<int> uniqueClasses;
  final int blankTop1Count;
  final Float32List flatOutput; // 19,836 floats
  final String? errorCode;
  final String? errorMessage;

  const RawRealInferenceOutput({
    required this.isSuccess,
    required this.inferenceTimeMs,
    required this.outputShape,
    required this.nanCount,
    required this.infCount,
    required this.outputMin,
    required this.outputMax,
    required this.outputMean,
    required this.outputStdDev,
    required this.rawArgmax,
    required this.uniqueClasses,
    required this.blankTop1Count,
    required this.flatOutput,
    this.errorCode,
    this.errorMessage,
  });

  factory RawRealInferenceOutput.failure({
    required String errorCode,
    required String errorMessage,
    int inferenceTimeMs = 0,
    List<int> outputShape = const [1, 29, 684],
  }) {
    return RawRealInferenceOutput(
      isSuccess: false,
      inferenceTimeMs: inferenceTimeMs,
      outputShape: outputShape,
      nanCount: 0,
      infCount: 0,
      outputMin: 0.0,
      outputMax: 0.0,
      outputMean: 0.0,
      outputStdDev: 0.0,
      rawArgmax: const [],
      uniqueClasses: const [],
      blankTop1Count: 0,
      flatOutput: Float32List(0),
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }
}

/// تقرير حالة الموديل للواجهة والتشخيص
class ModelPipelineStatus {
  final ModelLoadState state;
  final String stateName;
  final int modelSizeBytes;
  final double modelSizeMb;
  final List<int>? inputShape;
  final String? inputDtype;
  final List<int>? outputShape;
  final String? outputDtype;
  final int lastInferenceTimeMs;
  final bool isLastOutputValid;
  final bool isResponsive;
  final List<int>? lastArgmaxIds;
  final List<TimestepLogitDiagnostic> lastTopLogits;
  final int totalInferenceCount;
  final String? lastErrorCode;
  final String? lastErrorMessage;

  const ModelPipelineStatus({
    required this.state,
    required this.stateName,
    required this.modelSizeBytes,
    required this.modelSizeMb,
    this.inputShape,
    this.inputDtype,
    this.outputShape,
    this.outputDtype,
    required this.lastInferenceTimeMs,
    required this.isLastOutputValid,
    required this.isResponsive,
    this.lastArgmaxIds,
    this.lastTopLogits = const [],
    required this.totalInferenceCount,
    this.lastErrorCode,
    this.lastErrorMessage,
  });
}

/// IsharaTfliteService
/// خدمة تحميل واستنتاج TFLite المستقلة والمفحوصة صرامياً:
/// - تحميل الموديل مرة واحدة فقط (Singleton/Service Lifecycle).
/// - التحقق من سلامة بايتات الموديل وحجمه ومنع مؤشرات Git LFS.
/// - قراءة Tensors الحقيقية من الـ Interpreter ومطابقتها ([1,128,86,2] -> [1,29,684]).
/// - قفل الأمان المتزامن لمنع تصادم عمليات الاستنتاج (Inference Concurrency Guard).
/// - حساب الـ Argmax والـ Top Logits التشخيصية ومراقبة تغير الاستجابة.
class IsharaTfliteService {
  static const String modelAssetPath = 'assets/models/ishara_model.tflite';

  Interpreter? _interpreter;
  ModelLoadState _state = ModelLoadState.notLoaded;

  int _modelSizeBytes = 0;
  double _modelSizeMb = 0.0;
  int _modelLoadTimeMs = 0;

  List<int>? _inputShape;
  String? _inputDtype;
  List<int>? _outputShape;
  String? _outputDtype;

  String? _lastErrorCode;
  String? _lastErrorMessage;

  // إحصائيات ونتائج الاستنتاج
  bool _isInferenceRunning = false;
  int _lastInferenceTimeMs = 0;
  bool _isLastOutputValid = false;
  bool _isResponsive = false;
  List<int>? _previousArgmaxIds;
  List<int>? _lastArgmaxIds;
  List<TimestepLogitDiagnostic> _lastTopLogits = const [];
  int _totalInferenceCount = 0;

  // Getters
  ModelLoadState get state => _state;
  bool get isReady => _state == ModelLoadState.ready && _interpreter != null;
  bool get isInferenceRunning => _isInferenceRunning;
  int get modelSizeBytes => _modelSizeBytes;
  double get modelSizeMb => _modelSizeMb;
  List<int>? get inputShape => _inputShape;
  String? get inputDtype => _inputDtype;
  List<int>? get outputShape => _outputShape;
  String? get outputDtype => _outputDtype;
  int get lastInferenceTimeMs => _lastInferenceTimeMs;
  bool get isLastOutputValid => _isLastOutputValid;
  bool get isResponsive => _isResponsive;
  List<int>? get lastArgmaxIds => _lastArgmaxIds;
  List<TimestepLogitDiagnostic> get lastTopLogits => _lastTopLogits;
  int get totalInferenceCount => _totalInferenceCount;
  String? get lastErrorCode => _lastErrorCode;
  String? get lastErrorMessage => _lastErrorMessage;

  /// تهيئة وتحميل الموديل وفحص الـ Tensors الحقيقية
  Future<bool> initialize() async {
    if (_state == ModelLoadState.loading) return false;
    if (_state == ModelLoadState.ready && _interpreter != null) return true;

    _state = ModelLoadState.loading;
    _lastErrorCode = null;
    _lastErrorMessage = null;

    final stopwatch = Stopwatch()..start();

    try {
      // 1. تحميل بايتات ملف الموديل من الـ Asset
      ByteData assetData;
      try {
        assetData = await rootBundle.load(modelAssetPath);
      } catch (e) {
        _state = ModelLoadState.error;
        _lastErrorCode = 'E_MODEL_FILE_MISSING';
        _lastErrorMessage = 'Could not load asset: $modelAssetPath ($e)';
        debugPrint('[IsharaTfliteService] ❌ $_lastErrorCode: $_lastErrorMessage');
        return false;
      }

      final Uint8List modelBytes = assetData.buffer.asUint8List(
        assetData.offsetInBytes,
        assetData.lengthInBytes,
      );

      _modelSizeBytes = modelBytes.length;
      _modelSizeMb = _modelSizeBytes / (1024 * 1024);

      // 2. فحص سلامة الملف وحجمه ومنع مؤشرات Git LFS
      final fileValidation = IsharaModelValidator.validateModelBytes(
        modelBytes,
        assetPath: modelAssetPath,
      );

      if (!fileValidation.isValid) {
        _state = ModelLoadState.error;
        _lastErrorCode = fileValidation.errorCode ?? 'E_MODEL_FILE_TOO_SMALL';
        _lastErrorMessage = fileValidation.errorMessage ?? 'Invalid model asset';
        debugPrint('[IsharaTfliteService] ❌ $_lastErrorCode: $_lastErrorMessage');
        return false;
      }

      // 3. إنشاء الـ Interpreter لمرة واحدة فقط
      final options = InterpreterOptions()..threads = 2;

      try {
        _interpreter = Interpreter.fromBuffer(modelBytes, options: options);
      } catch (e) {
        _state = ModelLoadState.error;
        _lastErrorCode = 'E_INTERPRETER_CREATE_FAILED';
        _lastErrorMessage = 'Failed to create TFLite Interpreter: $e';
        debugPrint('[IsharaTfliteService] ❌ $_lastErrorCode: $_lastErrorMessage');
        return false;
      }

      // 4. قراءة Tensors الحقيقية من الموديل ومطابقتها
      final inTensor = _interpreter!.getInputTensor(0);
      final outTensor = _interpreter!.getOutputTensor(0);

      _inputShape = List<int>.from(inTensor.shape);
      _inputDtype = inTensor.type.toString();
      _outputShape = List<int>.from(outTensor.shape);
      _outputDtype = outTensor.type.toString();

      debugPrint('==================================================');
      debugPrint('REAL MODEL TENSORS:');
      debugPrint('Input:  $_inputDtype $_inputShape');
      debugPrint('Output: $_outputDtype $_outputShape');
      debugPrint('==================================================');

      final shapeError = IsharaModelValidator.validateTensorShapes(
        actualInputShape: _inputShape!,
        actualOutputShape: _outputShape!,
      );

      if (shapeError != null) {
        _interpreter?.close();
        _interpreter = null;
        _state = ModelLoadState.error;
        _lastErrorCode = shapeError.contains('E_INPUT_SHAPE') ? 'E_INPUT_SHAPE' : 'E_OUTPUT_SHAPE';
        _lastErrorMessage = shapeError;
        debugPrint('[IsharaTfliteService] ❌ Shape Mismatch: $shapeError');
        return false;
      }

      stopwatch.stop();
      _modelLoadTimeMs = stopwatch.elapsedMilliseconds;
      _state = ModelLoadState.ready;
      debugPrint('[IsharaTfliteService] ✅ Model loaded successfully in $_modelLoadTimeMs ms.');
      return true;
    } catch (e) {
      _state = ModelLoadState.error;
      _lastErrorCode = 'E_INTERPRETER_CREATE_FAILED';
      _lastErrorMessage = 'Unexpected initialization error: $e';
      debugPrint('[IsharaTfliteService] ❌ Exception: $e');
      return false;
    }
  }

  /// تشغيل استنتاج واحد آمن ومحمي ضد التزامن (Single Safe Inference)
  Future<InferenceResult?> runInference(ModelInputSequence inputSequence) async {
    if (_interpreter == null || _state != ModelLoadState.ready) {
      debugPrint('[IsharaTfliteService] Cannot run inference: Interpreter not ready');
      return null;
    }

    // 1. قفل الأمان لمنع تداخل عمليات الاستنتاج
    if (_isInferenceRunning) {
      debugPrint('[IsharaTfliteService] Inference skipped: previous inference still running');
      return null;
    }
    _isInferenceRunning = true;

    try {
      // 2. التحقق من سلامة المدخلات وخلوها من NaN / Inf
      if (inputSequence.nanCount > 0 || inputSequence.infCount > 0) {
        _lastErrorCode = 'E_INPUT_NAN';
        _lastErrorMessage = 'Input sequence contains NaN or Inf (NaN: ${inputSequence.nanCount}, Inf: ${inputSequence.infCount})';
        debugPrint('[IsharaTfliteService] ❌ $_lastErrorCode: $_lastErrorMessage');
        return null;
      }

      if (!listEquals(inputSequence.shape, IsharaModelValidator.expectedInputShape)) {
        _lastErrorCode = 'E_INPUT_SHAPE';
        _lastErrorMessage = 'Expected input ${IsharaModelValidator.expectedInputShape}, got ${inputSequence.shape}';
        debugPrint('[IsharaTfliteService] ❌ $_lastErrorCode: $_lastErrorMessage');
        return null;
      }

      // 3. تجهيز مصفوفة الإدخال [1, 128, 86, 2]
      final inputTensor = inputSequence.toNestedTensor();

      // 4. حجز مصفوفة المخرجات [1, 29, 684]
      final outputTensor = List.generate(
        1,
        (_) => List.generate(
          29,
          (_) => List<double>.filled(684, 0.0),
        ),
      );

      // 5. قياس وقت الاستنتاج بدقة
      final stopwatch = Stopwatch()..start();
      _interpreter!.run(inputTensor, outputTensor);
      stopwatch.stop();

      final inferenceMs = stopwatch.elapsedMilliseconds;
      _lastInferenceTimeMs = inferenceMs;
      _totalInferenceCount++;

      // 6. التحقق الصارم من صحة مصفوفة المخرجات وخلوها من NaN/Inf
      final outputValidation = IsharaModelValidator.validateOutputTensor(outputTensor);
      if (!outputValidation.isValid) {
        _isLastOutputValid = false;
        _lastErrorCode = outputValidation.errorCode ?? 'E_OUTPUT_NAN';
        _lastErrorMessage = outputValidation.errorMessage ?? 'Invalid output tensor';
        debugPrint('[IsharaTfliteService] ❌ Output validation failed: $_lastErrorMessage');
        return InferenceResult(
          isSuccess: false,
          inferenceTimeMs: inferenceMs,
          inputShape: _inputShape ?? IsharaModelValidator.expectedInputShape,
          outputShape: _outputShape ?? IsharaModelValidator.expectedOutputShape,
          argmaxIds: const [],
          topLogits: const [],
          isResponsive: false,
          nanCount: outputValidation.nanCount,
          infCount: outputValidation.infCount,
          errorCode: _lastErrorCode,
          errorMessage: _lastErrorMessage,
        );
      }

      _isLastOutputValid = true;
      _lastArgmaxIds = outputValidation.argmaxIds;
      _lastTopLogits = IsharaModelValidator.extractTopLogits(outputTensor);

      // 7. مقارنة النتائج بالتسلسل السابق للتأكد من استجابة الموديل وتغيره
      if (_previousArgmaxIds != null) {
        _isResponsive = IsharaModelValidator.hasOutputChanged(
          _previousArgmaxIds!,
          outputValidation.argmaxIds,
        );
      } else {
        _isResponsive = true; // أول استنتاج ناجح
      }
      _previousArgmaxIds = List<int>.from(outputValidation.argmaxIds);

      debugPrint('[IsharaTfliteService] ✅ Inference #$_totalInferenceCount succeeded in $inferenceMs ms (Argmax: ${_lastArgmaxIds!.take(8).toList()}...)');

      return InferenceResult(
        isSuccess: true,
        inferenceTimeMs: inferenceMs,
        inputShape: _inputShape ?? IsharaModelValidator.expectedInputShape,
        outputShape: _outputShape ?? IsharaModelValidator.expectedOutputShape,
        argmaxIds: _lastArgmaxIds!,
        topLogits: _lastTopLogits,
        isResponsive: _isResponsive,
        nanCount: 0,
        infCount: 0,
      );
    } catch (e) {
      _isLastOutputValid = false;
      _lastErrorCode = 'E_INFERENCE_FAILED';
      _lastErrorMessage = 'Interpreter run failed: $e';
      debugPrint('[IsharaTfliteService] ❌ Inference exception: $e');
      return null;
    } finally {
      _isInferenceRunning = false;
    }
  }

  /// تشغيل استنتاج تسلسل حقيقي على الـ Interpreter المشترك مع استخراج كافة الإحصائيات الخام
  Future<RawRealInferenceOutput> runRealSequenceInference(ModelInputSequence inputSequence) async {
    if (_interpreter == null || _state != ModelLoadState.ready) {
      return RawRealInferenceOutput.failure(
        errorCode: 'E_INTERPRETER_NOT_READY',
        errorMessage: 'Interpreter is not initialized or ready',
      );
    }

    if (_isInferenceRunning) {
      return RawRealInferenceOutput.failure(
        errorCode: 'E_INFERENCE_CONCURRENCY',
        errorMessage: 'Another inference is currently running',
      );
    }
    _isInferenceRunning = true;

    try {
      // 1. التحقق الصارم من سلامة المدخلات
      if (inputSequence.nanCount > 0) {
        return RawRealInferenceOutput.failure(
          errorCode: 'E_REAL_INPUT_NAN',
          errorMessage: 'Input contains ${inputSequence.nanCount} NaN values',
        );
      }
      if (inputSequence.infCount > 0) {
        return RawRealInferenceOutput.failure(
          errorCode: 'E_REAL_INPUT_INF',
          errorMessage: 'Input contains ${inputSequence.infCount} Infinity values',
        );
      }
      if (!listEquals(inputSequence.shape, IsharaModelValidator.expectedInputShape)) {
        return RawRealInferenceOutput.failure(
          errorCode: 'E_REAL_INPUT_SHAPE',
          errorMessage: 'Input shape must be ${IsharaModelValidator.expectedInputShape}, got ${inputSequence.shape}',
        );
      }

      // 2. تحويل التسلسل إلى مصفوفة متداخلة [1, 128, 86, 2]
      final inputTensor = inputSequence.toNestedTensor();

      // 3. حجز مصفوفة المخرجات [1, 29, 684]
      final outputTensor = List.generate(
        1,
        (_) => List.generate(
          29,
          (_) => List<double>.filled(684, 0.0),
        ),
      );

      // 4. قياس زمن الاستنتاج بالـ Stopwatch
      final stopwatch = Stopwatch()..start();
      _interpreter!.run(inputTensor, outputTensor);
      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMilliseconds;
      _lastInferenceTimeMs = elapsedMs;
      _totalInferenceCount++;

      // 5. استخراج الإحصائيات والمصفوفة المسطحة وخلوها من NaN/Inf
      final flatOutput = Float32List(29 * 684);
      final List<int> argmaxIds = [];
      int nanCount = 0;
      int infCount = 0;
      double minVal = double.infinity;
      double maxVal = -double.infinity;
      double sumVal = 0.0;

      int flatIdx = 0;
      for (int t = 0; t < 29; t++) {
        final row = outputTensor[0][t];
        int bestClass = 0;
        double bestScore = -double.infinity;

        for (int c = 0; c < 684; c++) {
          final val = row[c];
          flatOutput[flatIdx++] = val;

          if (val.isNaN) {
            nanCount++;
          } else if (val.isInfinite) {
            infCount++;
          } else {
            if (val < minVal) minVal = val;
            if (val > maxVal) maxVal = val;
            sumVal += val;
          }

          if (val > bestScore) {
            bestScore = val;
            bestClass = c;
          }
        }
        argmaxIds.add(bestClass);
      }

      // حساب Mean و Standard Deviation
      final totalFloats = 29 * 684;
      final meanVal = totalFloats > 0 ? (sumVal / totalFloats) : 0.0;
      double sumSquaredDiff = 0.0;
      for (int i = 0; i < totalFloats; i++) {
        final v = flatOutput[i];
        if (!v.isNaN && !v.isInfinite) {
          final d = v - meanVal;
          sumSquaredDiff += d * d;
        }
      }
      final stdDevVal = totalFloats > 0 ? math.sqrt(sumSquaredDiff / totalFloats) : 0.0;

      // الفئات الفريدة وعدد الفئة صفر
      final uniqueClasses = argmaxIds.toSet().toList()..sort();
      final blankTop1Count = argmaxIds.where((id) => id == 0).length;

      if (nanCount > 0) {
        return RawRealInferenceOutput.failure(
          errorCode: 'E_REAL_OUTPUT_NAN',
          errorMessage: 'Output contains $nanCount NaN values',
          inferenceTimeMs: elapsedMs,
        );
      }
      if (infCount > 0) {
        return RawRealInferenceOutput.failure(
          errorCode: 'E_REAL_OUTPUT_INF',
          errorMessage: 'Output contains $infCount Infinity values',
          inferenceTimeMs: elapsedMs,
        );
      }

      _isLastOutputValid = true;
      _lastArgmaxIds = argmaxIds;

      return RawRealInferenceOutput(
        isSuccess: true,
        inferenceTimeMs: elapsedMs,
        outputShape: const [1, 29, 684],
        nanCount: 0,
        infCount: 0,
        outputMin: minVal.isInfinite ? 0.0 : minVal,
        outputMax: maxVal.isInfinite ? 0.0 : maxVal,
        outputMean: meanVal,
        outputStdDev: stdDevVal,
        rawArgmax: argmaxIds,
        uniqueClasses: uniqueClasses,
        blankTop1Count: blankTop1Count,
        flatOutput: flatOutput,
      );
    } catch (e) {
      _isLastOutputValid = false;
      _lastErrorCode = 'E_INFERENCE_FAILED';
      _lastErrorMessage = 'Real sequence inference failed: $e';
      return RawRealInferenceOutput.failure(
        errorCode: 'E_INFERENCE_FAILED',
        errorMessage: 'Real sequence inference failed: $e',
      );
    } finally {
      _isInferenceRunning = false;
    }
  }

  /// تقرير الحالة اللحظي لخدمة الموديل
  ModelPipelineStatus getStatus() {
    return ModelPipelineStatus(
      state: _state,
      stateName: _state.displayName,
      modelSizeBytes: _modelSizeBytes,
      modelSizeMb: _modelSizeMb,
      inputShape: _inputShape,
      inputDtype: _inputDtype,
      outputShape: _outputShape,
      outputDtype: _outputDtype,
      lastInferenceTimeMs: _lastInferenceTimeMs,
      isLastOutputValid: _isLastOutputValid,
      isResponsive: _isResponsive,
      lastArgmaxIds: _lastArgmaxIds,
      lastTopLogits: _lastTopLogits,
      totalInferenceCount: _totalInferenceCount,
      lastErrorCode: _lastErrorCode,
      lastErrorMessage: _lastErrorMessage,
    );
  }

  /// التخلص من موارد الـ Interpreter
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _state = ModelLoadState.notLoaded;
  }
}
