import 'package:ishara/ml/preprocessing/ishara_normalizer.dart';

/// نتيجة معالجة النقاط المفقودة للإطار
class ImputationResult {
  final List<Point2D> points;
  final bool isImputedFromPrevious;
  final bool isZeroFilled;
  final bool isRawDetected;

  const ImputationResult({
    required this.points,
    required this.isImputedFromPrevious,
    required this.isZeroFilled,
    required this.isRawDetected,
  });
}

/// نتيجة تجميع أجزاء الإطار بعد معالجة الفقدان
class PreparedModelInputFrame {
  final List<Point2D> rightHand;
  final List<Point2D> leftHand;
  final List<Point2D> lips;
  final List<Point2D> body;

  /// إجمالي النقاط الـ 86 المجهزة
  final List<Point2D> all86PreparedPoints;

  /// عدد النقاط التي تم رصدها حقيقة من الكواشف (0..86)
  final int rawDetectedCount;

  /// عدد نقاط مصفوفة الموديل المجهزة (دائماً 86)
  final int modelArrayCount;

  /// عدد النقاط التي تم تعويضها (0..86)
  final int imputedCount;

  final bool rightHandImputed;
  final bool leftHandImputed;
  final bool lipsImputed;
  final bool bodyImputed;

  final DateTime timestamp;

  const PreparedModelInputFrame({
    required this.rightHand,
    required this.leftHand,
    required this.lips,
    required this.body,
    required this.all86PreparedPoints,
    required this.rawDetectedCount,
    required this.modelArrayCount,
    required this.imputedCount,
    required this.rightHandImputed,
    required this.leftHandImputed,
    required this.lipsImputed,
    required this.bodyImputed,
    required this.timestamp,
  });
}

/// IsharaMissingPointHandler
/// إدارة ومعالجة النقاط والمجموعات المفقودة مطابقة لـ datasetv2.py:
/// 1. في البث الحي (Real-time Streaming):
///    - إذا كانت المجموعة مفقودة أو أصفاراً: استخدام الإطار السليم السابق (Previous-Valid).
///    - إذا كان أول إطار: ملء المجموعة بالأصفار ([21,2] أو [19,2] أو [25,2]).
/// 2. تفريق صريح ودقيق بين:
///    - rawDetectedCount (النقاط الحقيقية المكتشفة).
///    - modelArrayCount (النقاط الإجمالية بالمصفوفة 86).
///    - imputedCount (النقاط المعوضة).
/// 3. توفير دالة Backward-Fill لليدين اليسرى واليمنى مطابقة لـ datasetv2.py
///    جاهزة للاستخدام داخل 128-Frame Sequence Buffer لاحقاً.
class IsharaMissingPointHandler {
  static const int countRightHand = 21;
  static const int countLeftHand = 21;
  static const int countLips = 19;
  static const int countBody = 25;
  static const int countTotal = 86;

  // الحفاظ على آخر إطارات خام صالحة لكل مجموعة
  List<Point2D>? _lastValidRightHand;
  List<Point2D>? _lastValidLeftHand;
  List<Point2D>? _lastValidLips;
  List<Point2D>? _lastValidBody;

  List<Point2D>? get lastValidRightHand => _lastValidRightHand;
  List<Point2D>? get lastValidLeftHand => _lastValidLeftHand;
  List<Point2D>? get lastValidLips => _lastValidLips;
  List<Point2D>? get lastValidBody => _lastValidBody;

  void reset() {
    _lastValidRightHand = null;
    _lastValidLeftHand = null;
    _lastValidLips = null;
    _lastValidBody = null;
  }

  /// معالجة إطار حي وتحضير النقاط الـ 86 مع حساب النقاط المكتشفة والمعوضة بدقة
  PreparedModelInputFrame handleFrame({
    required List<Point2D>? rawRightHand,
    required List<Point2D>? rawLeftHand,
    required List<Point2D>? rawLips,
    required List<Point2D>? rawBody,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();

    final rhRes = _processGroup(
      rawPoints: rawRightHand,
      expectedCount: countRightHand,
      groupName: 'RightHand',
      lastValid: _lastValidRightHand,
      onValid: (valid) => _lastValidRightHand = valid,
    );

    final lhRes = _processGroup(
      rawPoints: rawLeftHand,
      expectedCount: countLeftHand,
      groupName: 'LeftHand',
      lastValid: _lastValidLeftHand,
      onValid: (valid) => _lastValidLeftHand = valid,
    );

    final lipsRes = _processGroup(
      rawPoints: rawLips,
      expectedCount: countLips,
      groupName: 'Lips',
      lastValid: _lastValidLips,
      onValid: (valid) => _lastValidLips = valid,
    );

    final bodyRes = _processGroup(
      rawPoints: rawBody,
      expectedCount: countBody,
      groupName: 'Body',
      lastValid: _lastValidBody,
      onValid: (valid) => _lastValidBody = valid,
    );

    int rawDetected = 0;
    int imputed = 0;

    if (rhRes.isRawDetected) {
      rawDetected += countRightHand;
    } else {
      imputed += countRightHand;
    }

    if (lhRes.isRawDetected) {
      rawDetected += countLeftHand;
    } else {
      imputed += countLeftHand;
    }

    if (lipsRes.isRawDetected) {
      rawDetected += countLips;
    } else {
      imputed += countLips;
    }

    if (bodyRes.isRawDetected) {
      rawDetected += countBody;
    } else {
      imputed += countBody;
    }

    // تجميع الـ 86 نقطة بالترتيب الصارم: Right (21) + Left (21) + Lips (19) + Body (25)
    final List<Point2D> fullList = [
      ...rhRes.points,
      ...lhRes.points,
      ...lipsRes.points,
      ...bodyRes.points,
    ];

    return PreparedModelInputFrame(
      rightHand: rhRes.points,
      leftHand: lhRes.points,
      lips: lipsRes.points,
      body: bodyRes.points,
      all86PreparedPoints: fullList,
      rawDetectedCount: rawDetected,
      modelArrayCount: countTotal,
      imputedCount: imputed,
      rightHandImputed: !rhRes.isRawDetected,
      leftHandImputed: !lhRes.isRawDetected,
      lipsImputed: !lipsRes.isRawDetected,
      bodyImputed: !bodyRes.isRawDetected,
      timestamp: now,
    );
  }

  ImputationResult _processGroup({
    required List<Point2D>? rawPoints,
    required int expectedCount,
    required String groupName,
    required List<Point2D>? lastValid,
    required void Function(List<Point2D>) onValid,
  }) {
    bool isMissing = rawPoints == null || rawPoints.length != expectedCount;

    if (!isMissing) {
      // فحص هل جميع النقاط أصفار (sum == 0 في Python)
      double sumAbs = 0.0;
      for (final p in rawPoints) {
        sumAbs += p.x.abs() + p.y.abs();
      }
      if (sumAbs < 1e-7) {
        isMissing = true;
      }
    }

    if (isMissing) {
      if (lastValid != null && lastValid.length == expectedCount) {
        return ImputationResult(
          points: List.of(lastValid), // نسخة جديدة مستقلة
          isImputedFromPrevious: true,
          isZeroFilled: false,
          isRawDetected: false,
        );
      } else {
        return ImputationResult(
          points: List.generate(expectedCount, (_) => Point2D.zero),
          isImputedFromPrevious: false,
          isZeroFilled: true,
          isRawDetected: false,
        );
      }
    }

    // صالحة ومكتشفة حقيقة
    final cleanCopy = List.of(rawPoints!);
    onValid(cleanCopy);

    return ImputationResult(
      points: cleanCopy,
      isImputedFromPrevious: false,
      isZeroFilled: false,
      isRawDetected: true,
    );
  }

  /// تطبيق الـ Backward-Fill لليدين اليسرى واليمنى على تسلسل إطارات كامل
  /// مطابق حرفياً لكود التدريب datasetv2.py:
  /// ```python
  /// for ljoint_idx in range(len(left_joints) - 2, -1, -1):
  ///     if left_joints[ljoint_idx].sum() == 0:
  ///         left_joints[ljoint_idx] = left_joints[ljoint_idx + 1].copy()
  ///
  /// for rjoint_idx in range(len(right_joints) - 2, -1, -1):
  ///     if right_joints[rjoint_idx].sum() == 0:
  ///         right_joints[rjoint_idx] = right_joints[rjoint_idx + 1].copy()
  /// ```
  static void applyHandsBackwardFill({
    required List<List<Point2D>> leftHandSequence,
    required List<List<Point2D>> rightHandSequence,
  }) {
    // 1. Left Hand Backward Fill
    for (int i = leftHandSequence.length - 2; i >= 0; i--) {
      if (_isGroupZeros(leftHandSequence[i])) {
        leftHandSequence[i] = List.of(leftHandSequence[i + 1]);
      }
    }

    // 2. Right Hand Backward Fill
    for (int i = rightHandSequence.length - 2; i >= 0; i--) {
      if (_isGroupZeros(rightHandSequence[i])) {
        rightHandSequence[i] = List.of(rightHandSequence[i + 1]);
      }
    }
  }

  static bool _isGroupZeros(List<Point2D> group) {
    for (final p in group) {
      if (p.x.abs() >= 1e-7 || p.y.abs() >= 1e-7) {
        return false;
      }
    }
    return true;
  }
}
