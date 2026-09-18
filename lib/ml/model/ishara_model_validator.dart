import 'package:flutter/foundation.dart';

/// نتيجة التحقق من ملف الموديل
class ModelFileValidationResult {
  final bool isValid;
  final int sizeBytes;
  final double sizeMb;
  final String? errorCode;
  final String? errorMessage;

  const ModelFileValidationResult({
    required this.isValid,
    required this.sizeBytes,
    required this.sizeMb,
    this.errorCode,
    this.errorMessage,
  });

  factory ModelFileValidationResult.valid({required int sizeBytes}) {
    return ModelFileValidationResult(
      isValid: true,
      sizeBytes: sizeBytes,
      sizeMb: sizeBytes / (1024 * 1024),
    );
  }

  factory ModelFileValidationResult.error({
    required int sizeBytes,
    required String errorCode,
    required String errorMessage,
  }) {
    return ModelFileValidationResult(
      isValid: false,
      sizeBytes: sizeBytes,
      sizeMb: sizeBytes / (1024 * 1024),
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }
}

/// نتيجة التحقق من مخرجات الاستنتاج (Inference Output)
class ModelOutputValidationResult {
  final bool isValid;
  final int batchSize;
  final int timesteps;
  final int classCount;
  final int nanCount;
  final int infCount;
  final String? errorCode;
  final String? errorMessage;
  final List<int> argmaxIds;

  const ModelOutputValidationResult({
    required this.isValid,
    required this.batchSize,
    required this.timesteps,
    required this.classCount,
    required this.nanCount,
    required this.infCount,
    this.errorCode,
    this.errorMessage,
    required this.argmaxIds,
  });
}

/// تشخيص الفئات الأعلى احتمالاً لكل خطوة زمنية
class TimestepLogitDiagnostic {
  final int timestep;
  final int topClassId;
  final double topScore;

  const TimestepLogitDiagnostic({
    required this.timestep,
    required this.topClassId,
    required this.topScore,
  });

  @override
  String toString() => 't=$timestep: class=$topClassId, score=${topScore.toStringAsFixed(4)}';
}

/// مدقق نماذج ومصفوفات TFLite الصارم لتطبيق Ishara
class IsharaModelValidator {
  static const int minValidModelSizeBytes = 100 * 1024; // 100 KB
  static const List<int> expectedInputShape = [1, 128, 86, 2];
  static const List<int> expectedOutputShape = [1, 29, 684];

  /// 1. التحقق من سلامة بايتات ملف الموديل قبل تحميله في الذاكرة
  static ModelFileValidationResult validateModelBytes(Uint8List bytes, {String assetPath = 'assets/models/ishara_model.tflite'}) {
    final size = bytes.length;
    final sizeMb = size / (1024 * 1024);

    debugPrint('==================================================');
    debugPrint('MODEL FILE CHECK');
    debugPrint('Path: $assetPath');
    debugPrint('Size bytes: $size');
    debugPrint('Size MB: ${sizeMb.toStringAsFixed(2)} MB');
    debugPrint('==================================================');

    if (size == 0) {
      return ModelFileValidationResult.error(
        sizeBytes: 0,
        errorCode: 'E_MODEL_FILE_MISSING',
        errorMessage: 'Model file is empty or not found in assets',
      );
    }

    if (size < minValidModelSizeBytes) {
      // فحص هل الملف عبارة عن Git LFS pointer نصي
      final textPreview = String.fromCharCodes(bytes.take(100));
      if (textPreview.contains('version https://git-lfs.github.com/spec/v1')) {
        return ModelFileValidationResult.error(
          sizeBytes: size,
          errorCode: 'E_MODEL_LFS_POINTER',
          errorMessage: 'GIT_LFS_POINTER_NOT_MODEL (Pointer size: $size bytes)',
        );
      }

      return ModelFileValidationResult.error(
        sizeBytes: size,
        errorCode: 'E_MODEL_FILE_TOO_SMALL',
        errorMessage: 'INVALID_MODEL_ASSET (Size: $size bytes < 100 KB)',
      );
    }

    // فحص FlatBuffer magic identifier (TFL3)
    if (size >= 8) {
      final magic = String.fromCharCodes(bytes.sublist(4, 8));
      if (magic != 'TFL3') {
        debugPrint('[IsharaModelValidator] Warning: Magic bytes are "$magic" instead of TFL3');
      }
    }

    return ModelFileValidationResult.valid(sizeBytes: size);
  }

  /// 2. التحقق الصارم من أبعاد Input و Output Tensors عبر مقارنة القوائم الدقيقة
  static String? validateTensorShapes({
    required List<int> actualInputShape,
    required List<int> actualOutputShape,
  }) {
    if (!listEquals(actualInputShape, expectedInputShape)) {
      return 'E_INPUT_SHAPE (Expected: $expectedInputShape, Got: $actualInputShape)';
    }

    if (!listEquals(actualOutputShape, expectedOutputShape)) {
      return 'E_OUTPUT_SHAPE (Expected: $expectedOutputShape, Got: $actualOutputShape)';
    }

    return null; // متطابق تماماً
  }

  /// 3. فحص مصفوفة مخرجات الموديل [1, 29, 684] وخلوها من NaN / Inf
  static ModelOutputValidationResult validateOutputTensor(List<List<List<double>>> output) {
    if (output.isEmpty || output.length != 1) {
      return ModelOutputValidationResult(
        isValid: false,
        batchSize: output.length,
        timesteps: 0,
        classCount: 0,
        nanCount: 0,
        infCount: 0,
        errorCode: 'E_OUTPUT_SHAPE',
        errorMessage: 'Batch dimension must be 1, got ${output.length}',
        argmaxIds: const [],
      );
    }

    final batch0 = output[0];
    if (batch0.length != 29) {
      return ModelOutputValidationResult(
        isValid: false,
        batchSize: 1,
        timesteps: batch0.length,
        classCount: 0,
        nanCount: 0,
        infCount: 0,
        errorCode: 'E_OUTPUT_SHAPE',
        errorMessage: 'Expected 29 timesteps, got ${batch0.length}',
        argmaxIds: const [],
      );
    }

    int nanCount = 0;
    int infCount = 0;
    final List<int> argmaxIds = [];

    for (int t = 0; t < 29; t++) {
      final timestepClasses = batch0[t];
      if (timestepClasses.length != 684) {
        return ModelOutputValidationResult(
          isValid: false,
          batchSize: 1,
          timesteps: 29,
          classCount: timestepClasses.length,
          nanCount: nanCount,
          infCount: infCount,
          errorCode: 'E_OUTPUT_SHAPE',
          errorMessage: 'Expected 684 classes at timestep $t, got ${timestepClasses.length}',
          argmaxIds: const [],
        );
      }

      int maxClass = 0;
      double maxScore = -double.infinity;

      for (int c = 0; c < 684; c++) {
        final val = timestepClasses[c];
        if (val.isNaN) {
          nanCount++;
        } else if (val.isInfinite) {
          infCount++;
        } else if (val > maxScore) {
          maxScore = val;
          maxClass = c;
        }
      }

      argmaxIds.add(maxClass);
    }

    if (nanCount > 0 || infCount > 0) {
      return ModelOutputValidationResult(
        isValid: false,
        batchSize: 1,
        timesteps: 29,
        classCount: 684,
        nanCount: nanCount,
        infCount: infCount,
        errorCode: 'E_OUTPUT_NAN',
        errorMessage: 'NaN or Inf detected in model output (NaN: $nanCount, Inf: $infCount)',
        argmaxIds: argmaxIds,
      );
    }

    return ModelOutputValidationResult(
      isValid: true,
      batchSize: 1,
      timesteps: 29,
      classCount: 684,
      nanCount: 0,
      infCount: 0,
      argmaxIds: argmaxIds,
    );
  }

  /// 4. استخراج عينة تشخيصية للفئات الأعلى لكل خطوة زمنية (Top Logits Diagnostic)
  static List<TimestepLogitDiagnostic> extractTopLogits(
    List<List<List<double>>> output, {
    int sampleInterval = 6,
  }) {
    if (output.isEmpty || output[0].length != 29) return const [];
    final List<TimestepLogitDiagnostic> diagnostics = [];

    for (int t = 0; t < 29; t += sampleInterval) {
      final row = output[0][t];
      int bestClass = 0;
      double bestScore = -double.infinity;

      for (int c = 0; c < row.length; c++) {
        if (row[c] > bestScore) {
          bestScore = row[c];
          bestClass = c;
        }
      }

      diagnostics.add(TimestepLogitDiagnostic(
        timestep: t,
        topClassId: bestClass,
        topScore: bestScore,
      ));
    }

    return diagnostics;
  }

  /// 5. مقارنة مخرجين للتأكد من استجابة وتغير الموديل وعدم ثباته المصطنع
  static bool hasOutputChanged(List<int> previousArgmax, List<int> currentArgmax) {
    if (previousArgmax.isEmpty || currentArgmax.isEmpty) return false;
    if (previousArgmax.length != currentArgmax.length) return true;

    for (int i = 0; i < previousArgmax.length; i++) {
      if (previousArgmax[i] != currentArgmax[i]) {
        return true;
      }
    }

    return false;
  }
}
