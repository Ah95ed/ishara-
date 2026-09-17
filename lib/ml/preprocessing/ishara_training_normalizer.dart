import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:ishara/ml/preprocessing/ishara_missing_point_handler.dart';
import 'package:ishara/ml/preprocessing/ishara_normalizer.dart';

/// نتيجة تطبيع مجموعة مستقلة
class NormalizedSubsetOutput {
  final List<Point2D> points;
  final bool hasInvalidDenominator;
  final String? diagnosticNote;

  const NormalizedSubsetOutput({
    required this.points,
    this.hasInvalidDenominator = false,
    this.diagnosticNote,
  });
}

/// نتيجة التطبيع النهائي للإطار الـ 86 نقطة
class TrainingNormalizedOutput {
  final List<Point2D> rightHand;
  final List<Point2D> leftHand;
  final List<Point2D> lips;
  final List<Point2D> body;

  /// المصفوفة المدمجة بالترتيب الحرفي للتدريب:
  /// RightHand (0..20) + LeftHand (21..41) + Lips (42..60) + Body (61..85)
  final List<Point2D> all86NormalizedPoints;

  final bool hasInvalidDenominator;
  final String? failureReason;

  const TrainingNormalizedOutput({
    required this.rightHand,
    required this.leftHand,
    required this.lips,
    required this.body,
    required this.all86NormalizedPoints,
    this.hasInvalidDenominator = false,
    this.failureReason,
  });

  /// تحويل النقاط إلى مصفوفة [86, 2]
  List<List<double>> toMatrix() {
    return all86NormalizedPoints.map((p) => [p.x, p.y]).toList(growable: false);
  }
}

/// IsharaTrainingNormalizer
/// التطبيع التدريبي الصارم والمستقل المطابق لـ utils/datasetv2.py:
/// - normalize(rightHand)
/// - normalize(leftHand)
/// - normalize_face(lips)
/// - normalize_body(body)
/// لا يطبق أي تطبيع جماعي، بل يطبع كل مجموعة على حدة ثم يدمجها بالترتيب الصارم.
class IsharaTrainingNormalizer {
  static const double epsilon = 1e-8;

  /// تطبيع إطار مجهز من MissingPointHandler
  static TrainingNormalizedOutput normalizePreparedFrame(PreparedModelInputFrame frame) {
    final rh = normalizeGroup(frame.rightHand, 'RightHand');
    final lh = normalizeGroup(frame.leftHand, 'LeftHand');
    final lips = normalizeGroup(frame.lips, 'Lips');
    final body = normalizeGroup(frame.body, 'Body');

    final bool hasInvalid = rh.hasInvalidDenominator ||
        lh.hasInvalidDenominator ||
        lips.hasInvalidDenominator ||
        body.hasInvalidDenominator;

    final String? reason = rh.diagnosticNote ??
        lh.diagnosticNote ??
        lips.diagnosticNote ??
        body.diagnosticNote;

    // دمج المجموعات بالترتيب: Right (21) + Left (21) + Lips (19) + Body (25) = 86
    final List<Point2D> fullList = [
      ...rh.points,
      ...lh.points,
      ...lips.points,
      ...body.points,
    ];

    return TrainingNormalizedOutput(
      rightHand: rh.points,
      leftHand: lh.points,
      lips: lips.points,
      body: body.points,
      all86NormalizedPoints: fullList,
      hasInvalidDenominator: hasInvalid,
      failureReason: reason,
    );
  }

  /// الخوارزمية الرياضية الستة من datasetv2.py لكل مجموعة:
  /// 1. pose -= pose[0]
  /// 2. pose -= min(pose, axis=0)
  /// 3. pose /= max(max_vals)
  /// 4. pose -= mean(pose) (Scalar Global Mean)
  /// 5. pose /= max(abs(pose))
  /// 6. pose *= 0.5
  static NormalizedSubsetOutput normalizeGroup(List<Point2D> input, String groupName) {
    final int n = input.length;
    if (n == 0) {
      return const NormalizedSubsetOutput(points: []);
    }

    // إذا كانت المجموعة كلها أصفار (مفقودة في الإطار الأول مثلاً)
    double sumAbs = 0.0;
    for (final p in input) {
      sumAbs += p.x.abs() + p.y.abs();
    }
    if (sumAbs < epsilon) {
      return NormalizedSubsetOutput(
        points: List.generate(n, (_) => Point2D.zero),
      );
    }

    // إنشاء مصفوفة عمل مستقلة تماماً
    final List<double> workX = List.generate(n, (i) => input[i].x);
    final List<double> workY = List.generate(n, (i) => input[i].y);

    // 1. طرح أول نقطة pose[0]
    final double originX = workX[0];
    final double originY = workY[0];
    for (int i = 0; i < n; i++) {
      workX[i] -= originX;
      workY[i] -= originY;
    }

    // 2. طرح min(pose, axis=0)
    double minX = workX[0];
    double minY = workY[0];
    for (int i = 1; i < n; i++) {
      if (workX[i] < minX) minX = workX[i];
      if (workY[i] < minY) minY = workY[i];
    }
    for (int i = 0; i < n; i++) {
      workX[i] -= minX;
      workY[i] -= minY;
    }

    // 3. التحجيم: max_vals = max(pose, axis=0); pose /= max(max_vals)
    double maxX = workX[0];
    double maxY = workY[0];
    for (int i = 1; i < n; i++) {
      if (workX[i] > maxX) maxX = workX[i];
      if (workY[i] > maxY) maxY = workY[i];
    }
    final double scale = math.max(maxX, maxY);

    if (scale.abs() < epsilon) {
      debugPrint('[IsharaTrainingNormalizer] ⚠️ NORMALIZATION_INVALID_DENOMINATOR: Scale=0 in $groupName');
      return NormalizedSubsetOutput(
        points: List.generate(n, (_) => Point2D.zero),
        hasInvalidDenominator: true,
        diagnosticNote: 'NORMALIZATION_INVALID_DENOMINATOR (scale = 0)',
      );
    }

    for (int i = 0; i < n; i++) {
      workX[i] /= scale;
      workY[i] /= scale;
    }

    // 4. طرح Global Mean (Scalar عبر جميع قيم X و Y)
    double totalVal = 0.0;
    for (int i = 0; i < n; i++) {
      totalVal += workX[i] + workY[i];
    }
    final double globalMean = totalVal / (2.0 * n);
    for (int i = 0; i < n; i++) {
      workX[i] -= globalMean;
      workY[i] -= globalMean;
    }

    // 5. القسمة على max(abs(pose)) (Scalar واحد)
    double maxAbs = 0.0;
    for (int i = 0; i < n; i++) {
      if (workX[i].abs() > maxAbs) maxAbs = workX[i].abs();
      if (workY[i].abs() > maxAbs) maxAbs = workY[i].abs();
    }

    if (maxAbs.abs() < epsilon) {
      debugPrint('[IsharaTrainingNormalizer] ⚠️ NORMALIZATION_INVALID_DENOMINATOR: MaxAbs=0 in $groupName');
      return NormalizedSubsetOutput(
        points: List.generate(n, (_) => Point2D.zero),
        hasInvalidDenominator: true,
        diagnosticNote: 'NORMALIZATION_INVALID_DENOMINATOR (maxAbs = 0)',
      );
    }

    for (int i = 0; i < n; i++) {
      workX[i] /= maxAbs;
      workY[i] /= maxAbs;
    }

    // 6. الضرب في 0.5 للتوسيط داخل [-0.5, +0.5]
    final List<Point2D> result = List.generate(
      n,
      (i) => Point2D(workX[i] * 0.5, workY[i] * 0.5),
    );

    return NormalizedSubsetOutput(points: result);
  }
}
