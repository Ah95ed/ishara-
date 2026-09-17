import 'package:ishara/ml/preprocessing/ishara_missing_point_handler.dart';
import 'package:ishara/ml/preprocessing/ishara_normalizer.dart';
import 'package:ishara/ml/preprocessing/ishara_training_normalizer.dart';

/// تقرير التحقق النهائي من مدخل الموديل
class ModelInputValidationReport {
  final int rawDetectedCount; // 0..86
  final int modelArrayCount;  // 86
  final int imputedCount;     // 0..86
  final int nanCount;
  final int infCount;
  final String normalizationStatus; // 'MATCH' or 'ERROR'
  final bool isMatch;
  final List<List<double>> modelArray; // [86, 2]
  final String? errorMessage;

  const ModelInputValidationReport({
    required this.rawDetectedCount,
    required this.modelArrayCount,
    required this.imputedCount,
    required this.nanCount,
    required this.infCount,
    required this.normalizationStatus,
    required this.isMatch,
    required this.modelArray,
    this.errorMessage,
  });

  bool get hasInvalidNumbers => nanCount > 0 || infCount > 0;
}

/// IsharaModelInputValidator
/// الفاحص النهائي الصارم لمدخل الموديل [86, 2]:
/// 1. يفحص اكتمال حجم المصفوفة [86, 2].
/// 2. يكتشف أي قيمة NaN أو Infinity.
/// 3. يربط بين عدد النقاط المكتشفة حقيقة (rawDetectedCount) ومصفوفة الموديل المعوضة (modelArrayCount).
/// 4. يتحقق من نجاح عملية التطبيع ومطابقتها لمخرجات التدريب (MATCH أو ERROR).
class IsharaModelInputValidator {
  static ModelInputValidationReport validate({
    required PreparedModelInputFrame preparedFrame,
    required TrainingNormalizedOutput normalizedOutput,
  }) {
    int nanCount = 0;
    int infCount = 0;

    final List<Point2D> points = normalizedOutput.all86NormalizedPoints;
    final List<List<double>> matrix = [];

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.x.isNaN || p.y.isNaN) {
        nanCount++;
      }
      if (p.x.isInfinite || p.y.isInfinite) {
        infCount++;
      }
      matrix.add([p.x, p.y]);
    }

    final bool shapeValid = points.length == 86;
    final bool hasInvalidNumbers = nanCount > 0 || infCount > 0;
    final bool noDenominatorError = !normalizedOutput.hasInvalidDenominator;

    final bool isSuccess = shapeValid && !hasInvalidNumbers && noDenominatorError;
    final String status = isSuccess ? 'MATCH' : 'ERROR';

    String? error;
    if (!shapeValid) {
      error = 'Invalid shape: expected 86 points, got ${points.length}';
    } else if (hasInvalidNumbers) {
      error = 'Invalid numbers: NaN=$nanCount, Inf=$infCount';
    } else if (!noDenominatorError) {
      error = normalizedOutput.failureReason ?? 'NORMALIZATION_INVALID_DENOMINATOR';
    }

    return ModelInputValidationReport(
      rawDetectedCount: preparedFrame.rawDetectedCount,
      modelArrayCount: preparedFrame.modelArrayCount,
      imputedCount: preparedFrame.imputedCount,
      nanCount: nanCount,
      infCount: infCount,
      normalizationStatus: status,
      isMatch: isSuccess,
      modelArray: matrix,
      errorMessage: error,
    );
  }
}
