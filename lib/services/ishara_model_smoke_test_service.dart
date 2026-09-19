import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara/models/model_smoke_test_result.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// IsharaModelSmokeTestService
/// خدمة مخصصة لفحص واختبار نموذج TFLite خطوة بخطوة مع توليد تقرير فحص تفصيلي شامل.
class IsharaModelSmokeTestService {
  static const String defaultModelPath = 'assets/models/ishara_model.tflite';
  static const List<int> expectedInputShape = [1, 128, 86, 2];
  static const List<int> expectedOutputShape = [1, 29, 684];
  static const int minValidModelSizeBytes = 100 * 1024; // 100 KB

  /// تنفيذ فحص الدخان للموديل (Model Smoke Test) بالكامل
  Future<ModelSmokeTestResult> runSmokeTest({
    String modelPath = defaultModelPath,
  }) async {
    final capturedAt = DateTime.now();

    // ── المتغيرات التشخيصية لجميع مراحل الاختبار ──
    bool fileExists = false;
    int sizeBytes = 0;
    double sizeMb = 0.0;
    bool isLfsPointer = false;
    bool fileValidationPass = false;

    bool interpreterReady = false;
    int interpreterLoadTimeMs = 0;
    String? interpreterError;

    List<int>? actualInputShape;
    String? actualInputType;
    bool inputValidationPass = false;

    List<int>? actualOutputShape;
    String? actualOutputType;
    bool outputValidationPass = false;

    bool zeroInferencePass = false;
    int zeroInferenceTimeMs = 0;
    int nanCount = 0;
    int infCount = 0;
    double? outputMin;
    double? outputMax;
    List<double> firstOutputValues = [];

    bool secondInferencePass = false;
    bool outputChanged = false;
    double maxAbsoluteDifference = 0.0;

    String firstFailurePoint = 'NONE';
    String errorMessage = 'None';

    Uint8List? modelBytes;
    Interpreter? interpreter;

    try {
      // ══════════════════════════════════════════════════
      // TEST 1 — Model File Check
      // ══════════════════════════════════════════════════
      try {
        final byteData = await rootBundle.load(modelPath);
        modelBytes = byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );
        fileExists = true;
        sizeBytes = modelBytes.length;
        sizeMb = sizeBytes / (1024 * 1024);

        // فحص Git LFS Pointer
        if (sizeBytes >= 30) {
          final prefix = String.fromCharCodes(modelBytes.take(35));
          if (prefix.startsWith('version https://git-lfs.github.com/spec/v1')) {
            isLfsPointer = true;
          }
        }

        if (isLfsPointer) {
          fileValidationPass = false;
          firstFailurePoint = 'MODEL FILE (GIT_LFS_POINTER)';
          errorMessage = 'The model file is a Git LFS pointer text file, not the actual binary TFLite model.';
        } else if (sizeBytes < minValidModelSizeBytes) {
          fileValidationPass = false;
          firstFailurePoint = 'MODEL FILE (FILE_TOO_SMALL)';
          errorMessage = 'The model file is too small ($sizeBytes bytes). Real model is ~107 MB.';
        } else {
          fileValidationPass = true;
        }
      } catch (e) {
        fileExists = false;
        fileValidationPass = false;
        firstFailurePoint = 'MODEL FILE (NOT_FOUND)';
        errorMessage = 'Failed to load model asset: $e';
      }

      // إذا فشل فحص الملف، نخرج بالنتيجة الحالية
      if (!fileValidationPass || modelBytes == null) {
        return ModelSmokeTestResult(
          capturedAt: capturedAt,
          modelPath: modelPath,
          fileExists: fileExists,
          sizeBytes: sizeBytes,
          sizeMb: sizeMb,
          isLfsPointer: isLfsPointer,
          fileValidationPass: false,
          interpreterReady: false,
          interpreterLoadTimeMs: 0,
          inputValidationPass: false,
          outputValidationPass: false,
          zeroInferencePass: false,
          zeroInferenceTimeMs: 0,
          nanCount: 0,
          infCount: 0,
          secondInferencePass: false,
          outputChanged: false,
          maxAbsoluteDifference: 0.0,
          isOverallPass: false,
          firstFailurePoint: firstFailurePoint,
          errorMessage: errorMessage,
        );
      }

      // ══════════════════════════════════════════════════
      // TEST 2 — Interpreter Creation
      // ══════════════════════════════════════════════════
      final loadStopwatch = Stopwatch()..start();
      try {
        final options = InterpreterOptions()..threads = 2;
        interpreter = Interpreter.fromBuffer(modelBytes, options: options);
        loadStopwatch.stop();
        interpreterLoadTimeMs = loadStopwatch.elapsedMilliseconds;
        interpreterReady = true;
      } catch (e) {
        loadStopwatch.stop();
        interpreterLoadTimeMs = loadStopwatch.elapsedMilliseconds;
        interpreterReady = false;
        interpreterError = e.toString();
        firstFailurePoint = 'INTERPRETER';
        errorMessage = 'Interpreter.fromBuffer failed: $e';

        return ModelSmokeTestResult(
          capturedAt: capturedAt,
          modelPath: modelPath,
          fileExists: fileExists,
          sizeBytes: sizeBytes,
          sizeMb: sizeMb,
          isLfsPointer: isLfsPointer,
          fileValidationPass: true,
          interpreterReady: false,
          interpreterLoadTimeMs: interpreterLoadTimeMs,
          interpreterError: interpreterError,
          inputValidationPass: false,
          outputValidationPass: false,
          zeroInferencePass: false,
          zeroInferenceTimeMs: 0,
          nanCount: 0,
          infCount: 0,
          secondInferencePass: false,
          outputChanged: false,
          maxAbsoluteDifference: 0.0,
          isOverallPass: false,
          firstFailurePoint: firstFailurePoint,
          errorMessage: errorMessage,
        );
      }

      // ══════════════════════════════════════════════════
      // TEST 3 — Input Tensor Inspection
      // ══════════════════════════════════════════════════
      try {
        final inputTensors = interpreter.getInputTensors();
        if (inputTensors.isNotEmpty) {
          actualInputShape = inputTensors.first.shape;
          actualInputType = inputTensors.first.type.name;

          final bool shapeMatches = listEquals(actualInputShape, expectedInputShape);
          final bool typeMatches = actualInputType == 'float32';

          if (shapeMatches && typeMatches) {
            inputValidationPass = true;
          } else {
            inputValidationPass = false;
            firstFailurePoint = 'INPUT TENSOR';
            errorMessage = 'Input tensor mismatch. Shape: $actualInputShape (expected $expectedInputShape), Type: $actualInputType (expected float32).';
          }
        } else {
          inputValidationPass = false;
          firstFailurePoint = 'INPUT TENSOR';
          errorMessage = 'Interpreter has no input tensors.';
        }
      } catch (e) {
        inputValidationPass = false;
        firstFailurePoint = 'INPUT TENSOR';
        errorMessage = 'Failed to inspect input tensors: $e';
      }

      if (!inputValidationPass) {
        return ModelSmokeTestResult(
          capturedAt: capturedAt,
          modelPath: modelPath,
          fileExists: fileExists,
          sizeBytes: sizeBytes,
          sizeMb: sizeMb,
          isLfsPointer: isLfsPointer,
          fileValidationPass: true,
          interpreterReady: true,
          interpreterLoadTimeMs: interpreterLoadTimeMs,
          actualInputShape: actualInputShape,
          actualInputType: actualInputType,
          inputValidationPass: false,
          outputValidationPass: false,
          zeroInferencePass: false,
          zeroInferenceTimeMs: 0,
          nanCount: 0,
          infCount: 0,
          secondInferencePass: false,
          outputChanged: false,
          maxAbsoluteDifference: 0.0,
          isOverallPass: false,
          firstFailurePoint: firstFailurePoint,
          errorMessage: errorMessage,
        );
      }

      // ══════════════════════════════════════════════════
      // TEST 4 — Output Tensor Inspection
      // ══════════════════════════════════════════════════
      try {
        final outputTensors = interpreter.getOutputTensors();
        if (outputTensors.isNotEmpty) {
          actualOutputShape = outputTensors.first.shape;
          actualOutputType = outputTensors.first.type.name;

          final bool shapeMatches = listEquals(actualOutputShape, expectedOutputShape);
          final bool typeMatches = actualOutputType == 'float32';

          if (shapeMatches && typeMatches) {
            outputValidationPass = true;
          } else {
            outputValidationPass = false;
            firstFailurePoint = 'OUTPUT TENSOR';
            errorMessage = 'Output tensor mismatch. Shape: $actualOutputShape (expected $expectedOutputShape), Type: $actualOutputType (expected float32).';
          }
        } else {
          outputValidationPass = false;
          firstFailurePoint = 'OUTPUT TENSOR';
          errorMessage = 'Interpreter has no output tensors.';
        }
      } catch (e) {
        outputValidationPass = false;
        firstFailurePoint = 'OUTPUT TENSOR';
        errorMessage = 'Failed to inspect output tensors: $e';
      }

      if (!outputValidationPass) {
        return ModelSmokeTestResult(
          capturedAt: capturedAt,
          modelPath: modelPath,
          fileExists: fileExists,
          sizeBytes: sizeBytes,
          sizeMb: sizeMb,
          isLfsPointer: isLfsPointer,
          fileValidationPass: true,
          interpreterReady: true,
          interpreterLoadTimeMs: interpreterLoadTimeMs,
          actualInputShape: actualInputShape,
          actualInputType: actualInputType,
          inputValidationPass: true,
          actualOutputShape: actualOutputShape,
          actualOutputType: actualOutputType,
          outputValidationPass: false,
          zeroInferencePass: false,
          zeroInferenceTimeMs: 0,
          nanCount: 0,
          infCount: 0,
          secondInferencePass: false,
          outputChanged: false,
          maxAbsoluteDifference: 0.0,
          isOverallPass: false,
          firstFailurePoint: firstFailurePoint,
          errorMessage: errorMessage,
        );
      }

      // ══════════════════════════════════════════════════
      // TEST 5 & 6 — Dummy Input (Zero Input Test) & Output Validation
      // ══════════════════════════════════════════════════
      // مصفوفة إدخال أصفار [1, 128, 86, 2]
      final zeroInput = List.generate(
        1,
        (_) => List.generate(
          128,
          (_) => List.generate(
            86,
            (_) => List<double>.filled(2, 0.0),
          ),
        ),
      );

      // مصفوفة مخرجات مخصصة [1, 29, 684]
      final zeroOutput = List.generate(
        1,
        (_) => List.generate(
          29,
          (_) => List<double>.filled(684, 0.0),
        ),
      );

      final zeroStopwatch = Stopwatch()..start();
      try {
        interpreter.run(zeroInput, zeroOutput);
        zeroStopwatch.stop();
        zeroInferenceTimeMs = zeroStopwatch.elapsedMilliseconds;
        zeroInferencePass = true;
      } catch (e) {
        zeroStopwatch.stop();
        zeroInferenceTimeMs = zeroStopwatch.elapsedMilliseconds;
        zeroInferencePass = false;
        firstFailurePoint = 'ZERO INPUT INFERENCE';
        errorMessage = 'Inference run failed on zero input: $e';
      }

      if (!zeroInferencePass) {
        return ModelSmokeTestResult(
          capturedAt: capturedAt,
          modelPath: modelPath,
          fileExists: fileExists,
          sizeBytes: sizeBytes,
          sizeMb: sizeMb,
          isLfsPointer: isLfsPointer,
          fileValidationPass: true,
          interpreterReady: true,
          interpreterLoadTimeMs: interpreterLoadTimeMs,
          actualInputShape: actualInputShape,
          actualInputType: actualInputType,
          inputValidationPass: true,
          actualOutputShape: actualOutputShape,
          actualOutputType: actualOutputType,
          outputValidationPass: true,
          zeroInferencePass: false,
          zeroInferenceTimeMs: zeroInferenceTimeMs,
          nanCount: 0,
          infCount: 0,
          secondInferencePass: false,
          outputChanged: false,
          maxAbsoluteDifference: 0.0,
          isOverallPass: false,
          firstFailurePoint: firstFailurePoint,
          errorMessage: errorMessage,
        );
      }

      // فحص قيم المخرجات صفرية المدخل (NaN, Inf, Min, Max, First Values)
      double minVal = double.infinity;
      double maxVal = -double.infinity;

      final timestep0 = zeroOutput[0];
      for (int t = 0; t < 29; t++) {
        final classes = timestep0[t];
        for (int c = 0; c < 684; c++) {
          final val = classes[c];
          if (val.isNaN) {
            nanCount++;
          } else if (val.isInfinite) {
            infCount++;
          } else {
            if (val < minVal) minVal = val;
            if (val > maxVal) maxVal = val;
          }
        }
      }

      outputMin = minVal.isInfinite ? null : minVal;
      outputMax = maxVal.isInfinite ? null : maxVal;
      firstOutputValues = zeroOutput[0][0].take(5).toList();

      if (nanCount > 0 || infCount > 0) {
        firstFailurePoint = 'ZERO INPUT VALIDATION';
        errorMessage = 'Output tensor contains invalid numbers (NaN: $nanCount, Inf: $infCount).';
        return ModelSmokeTestResult(
          capturedAt: capturedAt,
          modelPath: modelPath,
          fileExists: fileExists,
          sizeBytes: sizeBytes,
          sizeMb: sizeMb,
          isLfsPointer: isLfsPointer,
          fileValidationPass: true,
          interpreterReady: true,
          interpreterLoadTimeMs: interpreterLoadTimeMs,
          actualInputShape: actualInputShape,
          actualInputType: actualInputType,
          inputValidationPass: true,
          actualOutputShape: actualOutputShape,
          actualOutputType: actualOutputType,
          outputValidationPass: true,
          zeroInferencePass: true,
          zeroInferenceTimeMs: zeroInferenceTimeMs,
          nanCount: nanCount,
          infCount: infCount,
          outputMin: outputMin,
          outputMax: outputMax,
          firstOutputValues: firstOutputValues,
          secondInferencePass: false,
          outputChanged: false,
          maxAbsoluteDifference: 0.0,
          isOverallPass: false,
          firstFailurePoint: firstFailurePoint,
          errorMessage: errorMessage,
        );
      }

      // ══════════════════════════════════════════════════
      // TEST 7 — Second Input Test (Responsiveness Check)
      // ══════════════════════════════════════════════════
      final secondInput = List.generate(
        1,
        (_) => List.generate(
          128,
          (t) => List.generate(
            86,
            (j) {
              final x = 0.1 * ((j % 5) + 1) / 5.0;
              final y = -0.1 * ((t % 5) + 1) / 5.0;
              return [x, y];
            },
          ),
        ),
      );

      final secondOutput = List.generate(
        1,
        (_) => List.generate(
          29,
          (_) => List<double>.filled(684, 0.0),
        ),
      );

      try {
        interpreter.run(secondInput, secondOutput);
        secondInferencePass = true;

        // حساب أقصى فرق مطلق بين مخرجات A ومخرجات B
        double maxDiff = 0.0;
        final outA = zeroOutput[0];
        final outB = secondOutput[0];

        for (int t = 0; t < 29; t++) {
          for (int c = 0; c < 684; c++) {
            final diff = (outA[t][c] - outB[t][c]).abs();
            if (diff > maxDiff) {
              maxDiff = diff;
            }
          }
        }

        maxAbsoluteDifference = maxDiff;
        outputChanged = maxDiff > 1e-4;

        if (!outputChanged) {
          firstFailurePoint = 'OUTPUT RESPONSIVENESS';
          errorMessage = 'Model outputs did not change between two completely different inputs (maxDiff: $maxDiff).';
        }
      } catch (e) {
        secondInferencePass = false;
        firstFailurePoint = 'SECOND INPUT INFERENCE';
        errorMessage = 'Second inference run failed: $e';
      }

      final isOverallPass = fileValidationPass &&
          interpreterReady &&
          inputValidationPass &&
          outputValidationPass &&
          zeroInferencePass &&
          nanCount == 0 &&
          infCount == 0 &&
          secondInferencePass &&
          outputChanged;

      return ModelSmokeTestResult(
        capturedAt: capturedAt,
        modelPath: modelPath,
        fileExists: fileExists,
        sizeBytes: sizeBytes,
        sizeMb: sizeMb,
        isLfsPointer: isLfsPointer,
        fileValidationPass: fileValidationPass,
        interpreterReady: interpreterReady,
        interpreterLoadTimeMs: interpreterLoadTimeMs,
        interpreterError: interpreterError,
        actualInputShape: actualInputShape,
        actualInputType: actualInputType,
        inputValidationPass: inputValidationPass,
        actualOutputShape: actualOutputShape,
        actualOutputType: actualOutputType,
        outputValidationPass: outputValidationPass,
        zeroInferencePass: zeroInferencePass,
        zeroInferenceTimeMs: zeroInferenceTimeMs,
        nanCount: nanCount,
        infCount: infCount,
        outputMin: outputMin,
        outputMax: outputMax,
        firstOutputValues: firstOutputValues,
        secondInferencePass: secondInferencePass,
        outputChanged: outputChanged,
        maxAbsoluteDifference: maxAbsoluteDifference,
        isOverallPass: isOverallPass,
        firstFailurePoint: isOverallPass ? 'NONE' : firstFailurePoint,
        errorMessage: isOverallPass ? 'None' : errorMessage,
      );
    } finally {
      // تحرير موارد المفسر دوماً لمنع تسرب الذاكرة
      try {
        interpreter?.close();
      } catch (_) {}
    }
  }
}
