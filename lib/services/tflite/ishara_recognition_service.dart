import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

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
  /// يتم التحميل مرة واحدة فقط عند بدء الخدمة.
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

      // طباعة مواصفات الموديل عند التحميل
      debugPrint('==================================================');
      debugPrint('[IsharaRecognitionService] Model loaded successfully');
      debugPrint('Input shape: $_inputShape');
      debugPrint('Output shape: $_outputShape');
      debugPrint('Input type: $_inputType');
      debugPrint('Output type: $_outputType');
      debugPrint('==================================================');

      // التحقق البرمجي الصارم من الأبعاد
      if (!_areShapesEqual(_inputShape, expectedInputShape)) {
        final errorMsg =
            'CRITICAL ERROR: Input shape mismatch! Expected: $expectedInputShape, Got: $_inputShape';
        debugPrint('[IsharaRecognitionService] ❌ $errorMsg');
        _releaseModel();
        throw StateError(errorMsg);
      }

      if (!_areShapesEqual(_outputShape, expectedOutputShape)) {
        final errorMsg =
            'CRITICAL ERROR: Output shape mismatch! Expected: $expectedOutputShape, Got: $_outputShape';
        debugPrint('[IsharaRecognitionService] ❌ $errorMsg');
        _releaseModel();
        throw StateError(errorMsg);
      }

      _isModelLoaded = true;
      return true;
    } catch (e, stack) {
      _isModelLoaded = false;
      _releaseModel();
      debugPrint('[IsharaRecognitionService] ❌ Failed to load model: $e\n$stack');
      return false;
    }
  }

  /// تشغيل الاستنتاج على مصفوفة الإدخال [1, 128, 86, 2]
  /// وإعادة مصفوفة الـ Logits بأبعاد [29, 684]
  List<List<double>>? runInference(List<List<List<double>>> frames128x86x2) {
    if (!_isModelLoaded || _interpreter == null) {
      debugPrint('[IsharaRecognitionService] Cannot run inference: Model not loaded');
      return null;
    }

    if (frames128x86x2.length != 128) {
      debugPrint(
        '[IsharaRecognitionService] Invalid frames length: ${frames128x86x2.length} (expected 128)',
      );
      return null;
    }

    try {
      // إعداد مصفوفة الدخل بأبعاد [1, 128, 86, 2]
      final input = [frames128x86x2];

      // إعداد مصفوفة الخرج بأبعاد [1, 29, 684]
      final output = List.generate(
        1,
        (_) => List.generate(
          29,
          (_) => List<double>.filled(684, 0.0),
        ),
      );

      // تشغيل الموديل
      _interpreter!.run(input, output);

      // إعادة مصفوفة الخطوات الزمنية [29, 684]
      return output[0];
    } catch (e, stack) {
      debugPrint('[IsharaRecognitionService] ❌ Inference error: $e\n$stack');
      return null;
    }
  }

  static bool _areShapesEqual(List<int>? a, List<int> b) {
    if (a == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
