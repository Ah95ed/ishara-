import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// نقطة ثنائية الأبعاد بنمط القيمة غير القابلة للتعديل (Immutable 2D Point)
class Point2D {
  final double x;
  final double y;

  const Point2D(this.x, this.y);

  static const Point2D zero = Point2D(0.0, 0.0);

  bool get isValid => !x.isNaN && !y.isNaN && !x.isInfinite && !y.isInfinite;
  bool get isZero => x.abs() < 1e-8 && y.abs() < 1e-8;

  List<double> toList() => [x, y];

  @override
  String toString() => '(${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Point2D &&
          runtimeType == other.runtimeType &&
          (x - other.x).abs() < 1e-6 &&
          (y - other.y).abs() < 1e-6;

  @override
  int get hashCode => Object.hash(x, y);
}

/// تقرير تفصيلي لتشخيص خطوات التطبيع لكل مجموعة
class GroupNormalizationDiagnostic {
  final String groupName;
  final int count;
  final Point2D referenceOrigin;
  final double minX;
  final double minY;
  final double scale;
  final double globalMean;
  final double maxAbs;
  final double finalMin;
  final double finalMax;
  final bool isDegenerate;
  final String? failureReason;

  const GroupNormalizationDiagnostic({
    required this.groupName,
    required this.count,
    required this.referenceOrigin,
    required this.minX,
    required this.minY,
    required this.scale,
    required this.globalMean,
    required this.maxAbs,
    required this.finalMin,
    required this.finalMax,
    this.isDegenerate = false,
    this.failureReason,
  });

  void logDiagnostic({List<Point2D>? rawPoints, List<Point2D>? normPoints}) {
    debugPrint('==================================================');
    debugPrint('[$groupName NORMALIZATION DIAGNOSTIC]');
    debugPrint('Points count: $count');
    debugPrint('Reference Origin (P0): $referenceOrigin');
    debugPrint(
      'Min X: ${minX.toStringAsFixed(6)}, Min Y: ${minY.toStringAsFixed(6)}',
    );
    debugPrint('Scale (max(maxX, maxY)): ${scale.toStringAsFixed(6)}');
    debugPrint(
      'Global Mean (scalar across all X&Y): ${globalMean.toStringAsFixed(6)}',
    );
    debugPrint('MaxAbs (scalar across all X&Y): ${maxAbs.toStringAsFixed(6)}');
    debugPrint(
      'Final Range: [${finalMin.toStringAsFixed(6)}, ${finalMax.toStringAsFixed(6)}]',
    );
    if (failureReason != null) {
      debugPrint('⚠️ Warning/Failure: $failureReason');
    }
    if (rawPoints != null && rawPoints.isNotEmpty) {
      debugPrint('RAW Points (sample):');
      final maxShow = math.min(rawPoints.length, 3);
      for (int i = 0; i < maxShow; i++) {
        debugPrint('  Raw P$i = ${rawPoints[i]}');
      }
    }
    if (normPoints != null && normPoints.isNotEmpty) {
      debugPrint('NORMALIZED Points (sample):');
      final maxShow = math.min(normPoints.length, 3);
      for (int i = 0; i < maxShow; i++) {
        debugPrint('  Norm P$i = ${normPoints[i]}');
      }
    }
    debugPrint('==================================================');
  }
}

/// نتيجة تطبيع مجموعة مستقلة مع مؤشراتها التشخيصية
class NormalizedGroupResult {
  final List<Point2D> points;
  final GroupNormalizationDiagnostic diagnostic;
  final bool usedPreviousFrameFallback;

  const NormalizedGroupResult({
    required this.points,
    required this.diagnostic,
    this.usedPreviousFrameFallback = false,
  });
}

/// نتيجة التطبيع الشامل لكامل الإطار الـ 86 نقطة
class FullNormalizedFrameResult {
  final List<Point2D> rightHand;
  final List<Point2D> leftHand;
  final List<Point2D> lips;
  final List<Point2D> body;

  /// المصفوفة المدمجة بالترتيب الحرفي للتدريب:
  /// RightHand (0..20) + LeftHand (21..41) + Lips (42..60) + Body (61..85)
  final List<Point2D> all86Keypoints;

  final GroupNormalizationDiagnostic rightHandDiag;
  final GroupNormalizationDiagnostic leftHandDiag;
  final GroupNormalizationDiagnostic lipsDiag;
  final GroupNormalizationDiagnostic bodyDiag;

  final DateTime timestamp;
  final int validNormalizedCount;
  final int nanCount;
  final int infCount;

  const FullNormalizedFrameResult({
    required this.rightHand,
    required this.leftHand,
    required this.lips,
    required this.body,
    required this.all86Keypoints,
    required this.rightHandDiag,
    required this.leftHandDiag,
    required this.lipsDiag,
    required this.bodyDiag,
    required this.timestamp,
    required this.validNormalizedCount,
    required this.nanCount,
    required this.infCount,
  });

  bool get hasInvalidNumbers => nanCount > 0 || infCount > 0;
  bool get isTrainingMatch => all86Keypoints.length == 86 && !hasInvalidNumbers;

  /// تحويل الناتج إلى مصفوفة ثنائية الأبعاد [86, 2]
  List<List<double>> toMatrix() {
    return all86Keypoints.map((p) => [p.x, p.y]).toList(growable: false);
  }

  /// تحويل الناتج إلى Float32List مسطحة بطول 172
  Float32List toFlatFloat32List() {
    final arr = Float32List(all86Keypoints.length * 2);
    for (int i = 0; i < all86Keypoints.length; i++) {
      arr[i * 2] = all86Keypoints[i].x;
      arr[i * 2 + 1] = all86Keypoints[i].y;
    }
    return arr;
  }
}

/// IsharaNormalizer
/// التطبيق الحرفي والمطابق رياضياً بنسبة 100% لخوارزمية التطبيع في ملف التدريب الأصلي:
/// utils/datasetv2.py (PoseDatasetV2)
///
/// القواعد الصارمة:
/// 1. يتم تطبيع كل مجموعة بشكل مستقل تماماً (RightHand, LeftHand, Lips, Body).
/// 2. لا يتم تعديل القوائم الأصلية in-place إطلاقاً.
/// 3. لا يتم تطبيق أي Data Augmentation أثناء التشغيل الحي.
/// 4. المرحلة 1: طرح أول نقطة pose[0] كمرجع.
/// 5. المرحلة 2: طرح القيمة الصغرى لكل محور min(axis=0).
/// 6. المرحلة 3: القسمة على سكيل واحد مقداره max(maxX, maxY).
/// 7. المرحلة 4: طرح Global Mean واحد لكافة قيم X و Y المدمجة (Scalar Mean).
/// 8. المرحلة 5: القسمة على MaxAbs واحد لكافة القيم (Scalar MaxAbs).
/// 9. المرحلة 6: الضرب في 0.5 للتوسيط داخل [-0.5, +0.5].
/// 10. حماية من القسمة على صفر مع حفظ الإطار السابق (Carry-Forward) للمجموعات المفقودة.
class IsharaNormalizer {
  static const double epsilon = 1e-8;

  // الأحجام الثابتة المعتمدة من التدريب
  static const int countRightHand = 21;
  static const int countLeftHand = 21;
  static const int countLips = 19;
  static const int countBody = 25;
  static const int countTotal = 86;

  // فهارس الشفاه الخارجية الـ 19 الأصلية من FaceMesh
  static const List<int> originalLipMeshIndices = [
    0,
    17,
    37,
    39,
    40,
    61,
    84,
    91,
    146,
    181,
    185,
    267,
    269,
    270,
    291,
    314,
    321,
    375,
    405,
  ];

  // الحالة الداخلية للاحتفاظ بآخر إطارات سليمة (Stateful Carry-Forward)
  List<Point2D>? _previousRightHand;
  List<Point2D>? _previousLeftHand;
  List<Point2D>? _previousLips;
  List<Point2D>? _previousBody;

  List<Point2D>? get previousRightHand => _previousRightHand;
  List<Point2D>? get previousLeftHand => _previousLeftHand;
  List<Point2D>? get previousLips => _previousLips;
  List<Point2D>? get previousBody => _previousBody;

  /// إعادة تعيين الإطارات السابقة
  void reset() {
    _previousRightHand = null;
    _previousLeftHand = null;
    _previousLips = null;
    _previousBody = null;
  }

  // ── Public API المستقلة لكل مجموعة كما طلب العميل ──

  /// تطبيع اليد اليمنى (21 نقطة)
  NormalizedGroupResult normalizeRightHand(List<Point2D>? points) {
    return _processGroup(
      rawPoints: points,
      expectedCount: countRightHand,
      groupName: 'RightHand',
      previousValid: _previousRightHand,
      onValidResult: (result) => _previousRightHand = result,
    );
  }

  /// تطبيع اليد اليسرى (21 نقطة)
  NormalizedGroupResult normalizeLeftHand(List<Point2D>? points) {
    return _processGroup(
      rawPoints: points,
      expectedCount: countLeftHand,
      groupName: 'LeftHand',
      previousValid: _previousLeftHand,
      onValidResult: (result) => _previousLeftHand = result,
    );
  }

  /// تطبيع الشفاه (19 نقطة)
  NormalizedGroupResult normalizeLips(List<Point2D>? points) {
    return _processGroup(
      rawPoints: points,
      expectedCount: countLips,
      groupName: 'Lips',
      previousValid: _previousLips,
      onValidResult: (result) => _previousLips = result,
    );
  }

  /// تطبيع الجسم العلوي والرأس (25 نقطة)
  NormalizedGroupResult normalizeBody(List<Point2D>? points) {
    return _processGroup(
      rawPoints: points,
      expectedCount: countBody,
      groupName: 'Body',
      previousValid: _previousBody,
      onValidResult: (result) => _previousBody = result,
    );
  }

  /// تطبيع إطار كامل من الـ 4 مجموعات ودمجها بالترتيب الصارم [86, 2]
  FullNormalizedFrameResult processFrame({
    required List<Point2D>? rawRightHand,
    required List<Point2D>? rawLeftHand,
    required List<Point2D>? rawLips,
    required List<Point2D>? rawBody,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();

    final rhResult = normalizeRightHand(rawRightHand);
    final lhResult = normalizeLeftHand(rawLeftHand);
    final lipsResult = normalizeLips(rawLips);
    final bodyResult = normalizeBody(rawBody);

    // دمج المجموعات بالترتيب التدريبي الدقيق:
    // RightHand (21) + LeftHand (21) + Lips (19) + Body (25) = 86
    final List<Point2D> fullList = List.generate(countTotal, (i) {
      if (i < 21) {
        return rhResult.points[i];
      } else if (i < 42) {
        return lhResult.points[i - 21];
      } else if (i < 61) {
        return lipsResult.points[i - 42];
      } else {
        return bodyResult.points[i - 61];
      }
    });

    int validCount = 0;
    int nanCount = 0;
    int infCount = 0;

    for (final p in fullList) {
      if (p.x.isNaN || p.y.isNaN) {
        nanCount++;
      } else if (p.x.isInfinite || p.y.isInfinite) {
        infCount++;
      } else {
        validCount++;
      }
    }

    return FullNormalizedFrameResult(
      rightHand: rhResult.points,
      leftHand: lhResult.points,
      lips: lipsResult.points,
      body: bodyResult.points,
      all86Keypoints: fullList,
      rightHandDiag: rhResult.diagnostic,
      leftHandDiag: lhResult.diagnostic,
      lipsDiag: lipsResult.diagnostic,
      bodyDiag: bodyResult.diagnostic,
      timestamp: now,
      validNormalizedCount: validCount,
      nanCount: nanCount,
      infCount: infCount,
    );
  }

  /// معالجة المجموعة مع تطبيق فحص الفقدان (Missing group check) واستراتيجية التدريب
  NormalizedGroupResult _processGroup({
    required List<Point2D>? rawPoints,
    required int expectedCount,
    required String groupName,
    required List<Point2D>? previousValid,
    required void Function(List<Point2D>) onValidResult,
  }) {
    // 1. فحص هل المجموعة موجودة وصالحة
    bool isMissing = rawPoints == null || rawPoints.length != expectedCount;

    if (!isMissing) {
      // التحقق هل مجموع النقاط أصفار بالكامل (كما في Python: pose.sum() == 0)
      double sumAbs = 0.0;
      for (final p in rawPoints) {
        sumAbs += p.x.abs() + p.y.abs();
      }
      if (sumAbs < epsilon) {
        isMissing = true;
      }
    }

    if (isMissing) {
      // تطبيق استراتيجية التدريب: استخدام السابق إذا وجد، وإلا أصفار
      if (previousValid != null && previousValid.length == expectedCount) {
        final diag = GroupNormalizationDiagnostic(
          groupName: groupName,
          count: expectedCount,
          referenceOrigin: Point2D.zero,
          minX: 0.0,
          minY: 0.0,
          scale: 1.0,
          globalMean: 0.0,
          maxAbs: 1.0,
          finalMin: 0.0,
          finalMax: 0.0,
          isDegenerate: true,
          failureReason: 'GROUP_MISSING_USED_PREVIOUS_FRAME',
        );
        return NormalizedGroupResult(
          points: List.of(previousValid), // نسخة جديدة غير قابلة للتعديل العرضي
          diagnostic: diag,
          usedPreviousFrameFallback: true,
        );
      } else {
        final zeros = List.generate(expectedCount, (_) => Point2D.zero);
        final diag = GroupNormalizationDiagnostic(
          groupName: groupName,
          count: expectedCount,
          referenceOrigin: Point2D.zero,
          minX: 0.0,
          minY: 0.0,
          scale: 1.0,
          globalMean: 0.0,
          maxAbs: 1.0,
          finalMin: 0.0,
          finalMax: 0.0,
          isDegenerate: true,
          failureReason: 'GROUP_MISSING_INITIALIZED_ZEROS',
        );
        return NormalizedGroupResult(
          points: zeros,
          diagnostic: diag,
          usedPreviousFrameFallback: false,
        );
      }
    }

    // 2. تطبيق خوارزمية التطبيع الحرفية
    final normResult = normalizeRawPoints(rawPoints!, groupName: groupName);

    if (normResult.diagnostic.isDegenerate) {
      // في حالة الشذوذ الرياضي (Degenerate)
      if (previousValid != null && previousValid.length == expectedCount) {
        return NormalizedGroupResult(
          points: List.of(previousValid),
          diagnostic: normResult.diagnostic,
          usedPreviousFrameFallback: true,
        );
      }
    } else {
      // حفظ الإطار السليم للاستخدام المستقبلي
      onValidResult(normResult.points);
    }

    return normResult;
  }

  /// الخوارزمية الرياضية الصرفة (Pure Mathematical Function)
  /// لا تعدل المدخلات in-place إطلاقاً
  static NormalizedGroupResult normalizeRawPoints(
    List<Point2D> inputPoints, {
    String groupName = 'Group',
  }) {
    final int n = inputPoints.length;
    if (n == 0) {
      return NormalizedGroupResult(
        points: const [],
        diagnostic: GroupNormalizationDiagnostic(
          groupName: groupName,
          count: 0,
          referenceOrigin: Point2D.zero,
          minX: 0,
          minY: 0,
          scale: 0,
          globalMean: 0,
          maxAbs: 0,
          finalMin: 0,
          finalMax: 0,
          isDegenerate: true,
          failureReason: 'EMPTY_POINTS',
        ),
      );
    }

    // إنشاء مصفوفة عمل جديدة تماماً [N, 2]
    final List<double> workX = List.generate(n, (i) => inputPoints[i].x);
    final List<double> workY = List.generate(n, (i) => inputPoints[i].y);

    // ── المرحلة الأولى: طرح أول نقطة pose[0] ──
    final double originX = workX[0];
    final double originY = workY[0];
    final Point2D refOrigin = Point2D(originX, originY);

    for (int i = 0; i < n; i++) {
      workX[i] -= originX;
      workY[i] -= originY;
    }

    // ── المرحلة الثانية: طرح Minimum X و Y ──
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

    // ── المرحلة الثالثة: Scale = max(maxX, maxY) (Scalar واحد) ──
    double maxX = workX[0];
    double maxY = workY[0];
    for (int i = 1; i < n; i++) {
      if (workX[i] > maxX) maxX = workX[i];
      if (workY[i] > maxY) maxY = workY[i];
    }

    final double scale = math.max(maxX, maxY);

    if (scale.abs() < epsilon) {
      return NormalizedGroupResult(
        points: List.generate(n, (_) => Point2D.zero),
        diagnostic: GroupNormalizationDiagnostic(
          groupName: groupName,
          count: n,
          referenceOrigin: refOrigin,
          minX: minX,
          minY: minY,
          scale: scale,
          globalMean: 0.0,
          maxAbs: 0.0,
          finalMin: 0.0,
          finalMax: 0.0,
          isDegenerate: true,
          failureReason: 'NORMALIZATION_INVALID_SCALE',
        ),
      );
    }

    for (int i = 0; i < n; i++) {
      workX[i] /= scale;
      workY[i] /= scale;
    }

    // ── المرحلة الرابعة: Global Mean لجميع قيم X و Y المدمجة (Scalar Mean) ──
    double sumAllValues = 0.0;
    for (int i = 0; i < n; i++) {
      sumAllValues += workX[i] + workY[i];
    }
    final double globalMean = sumAllValues / (2.0 * n);

    for (int i = 0; i < n; i++) {
      workX[i] -= globalMean;
      workY[i] -= globalMean;
    }

    // ── المرحلة الخامسة: Maximum Absolute Value (Scalar واحد) ──
    double maxAbs = 0.0;
    for (int i = 0; i < n; i++) {
      final absX = workX[i].abs();
      final absY = workY[i].abs();
      if (absX > maxAbs) maxAbs = absX;
      if (absY > maxAbs) maxAbs = absY;
    }

    if (maxAbs.abs() < epsilon) {
      return NormalizedGroupResult(
        points: List.generate(n, (_) => Point2D.zero),
        diagnostic: GroupNormalizationDiagnostic(
          groupName: groupName,
          count: n,
          referenceOrigin: refOrigin,
          minX: minX,
          minY: minY,
          scale: scale,
          globalMean: globalMean,
          maxAbs: maxAbs,
          finalMin: 0.0,
          finalMax: 0.0,
          isDegenerate: true,
          failureReason: 'NORMALIZATION_INVALID_MAX_ABS',
        ),
      );
    }

    for (int i = 0; i < n; i++) {
      workX[i] /= maxAbs;
      workY[i] /= maxAbs;
    }

    // ── المرحلة السادسة: الضرب في 0.5 ──
    double finalMin = double.infinity;
    double finalMax = -double.infinity;
    final List<Point2D> normalizedPoints = List.generate(n, (i) {
      final fx = workX[i] * 0.5;
      final fy = workY[i] * 0.5;
      if (fx < finalMin) finalMin = fx;
      if (fy < finalMin) finalMin = fy;
      if (fx > finalMax) finalMax = fx;
      if (fy > finalMax) finalMax = fy;
      return Point2D(fx, fy);
    });

    final diag = GroupNormalizationDiagnostic(
      groupName: groupName,
      count: n,
      referenceOrigin: refOrigin,
      minX: minX,
      minY: minY,
      scale: scale,
      globalMean: globalMean,
      maxAbs: maxAbs,
      finalMin: finalMin,
      finalMax: finalMax,
      isDegenerate: false,
    );

    return NormalizedGroupResult(points: normalizedPoints, diagnostic: diag);
  }
}
