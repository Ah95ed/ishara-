/// نتيجة تقييم حضور عناصر الجسم في الإطار
class FramePresenceResult {
  final bool headPresent;
  final bool facePresent;
  final bool lipsPresent;
  final bool leftHandPresent;
  final bool rightHandPresent;
  final double handConfidence;
  final double headConfidence;

  const FramePresenceResult({
    required this.headPresent,
    required this.facePresent,
    required this.lipsPresent,
    required this.leftHandPresent,
    required this.rightHandPresent,
    this.handConfidence = 0.0,
    this.headConfidence = 0.0,
  });

  /// تحقق شرط: وجود يد واحدة على الأقل
  bool get hasAtLeastOneHand => rightHandPresent || leftHandPresent;

  /// تحقق شرط: الرأس أو الوجه متواجد
  bool get hasHeadOrFace => headPresent || facePresent;

  /// الشرط الإلزامي للمتطلب 1 و 2:
  /// ممنوع الترجمة أو بدء إشارة بدون Head/Face AND at least one Hand
  bool get isSignEligible => hasHeadOrFace && hasAtLeastOneHand;

  static const FramePresenceResult empty = FramePresenceResult(
    headPresent: false,
    facePresent: false,
    lipsPresent: false,
    leftHandPresent: false,
    rightHandPresent: false,
  );
}

/// كاشف ومتحقق الحضور الصارم (SignPresenceValidator)
///
/// يفرض القاعدة الإلزامية:
/// إذا لم يكن هناك: Head / Face detected AND at least one Hand detected
/// يجب أن تكون الحالة: NO_SIGN
/// ولا يتم تشغيل ترجمة أو إظهار كلمة أو إضافة Gloss حتى لو أعطى الموديل Class.
class SignPresenceValidator {
  final double minHandConfidence;
  final double minHeadConfidence;
  final double minValidKeypointRatio;

  // إحصائيات التتبع الزمني
  int _consecutiveValidPresenceFrames = 0;
  int _consecutiveMissingHandFrames = 0;
  int _consecutiveMissingHeadFrames = 0;

  SignPresenceValidator({
    this.minHandConfidence = 0.40,
    this.minHeadConfidence = 0.35,
    this.minValidKeypointRatio = 0.60,
  });

  int get consecutiveValidPresenceFrames => _consecutiveValidPresenceFrames;
  int get consecutiveMissingHandFrames => _consecutiveMissingHandFrames;
  int get consecutiveMissingHeadFrames => _consecutiveMissingHeadFrames;

  /// تقييم الحضور لإطار مفرد
  FramePresenceResult evaluatePresence({
    List<List<double>>? rightHand,
    List<List<double>>? leftHand,
    List<List<double>>? lips,
    List<List<double>>? body,
    double rightHandConfidence = 0.0,
    double leftHandConfidence = 0.0,
    double headConfidence = 0.0,
  }) {
    final bool rightHandPresent = _isLandmarkGroupValid(rightHand, 21) &&
        rightHandConfidence >= minHandConfidence;

    final bool leftHandPresent = _isLandmarkGroupValid(leftHand, 21) &&
        leftHandConfidence >= minHandConfidence;

    final bool lipsPresent = _isLandmarkGroupValid(lips, 19);

    // نقاط الرأس في MediaPipe Pose تشمل 0..10 (الأنف، العيون، الآذان، الشفاه)
    // أو إذا كانت نقاط الشفاه أو الوجه متوفرة
    bool headPresent = false;
    double resolvedHeadConf = headConfidence;

    if (body != null && body.length >= 11) {
      // فحص نقاط الرأس (0: Nose, 1..6: Eyes, 7..8: Ears, 9..10: Mouth)
      int validHeadPoints = 0;
      for (int i = 0; i < 11; i++) {
        if (!_isZeroPoint(body[i])) {
          validHeadPoints++;
        }
      }
      if (validHeadPoints >= 4) {
        headPresent = true;
        resolvedHeadConf = (validHeadPoints / 11.0);
      }
    } else if (lipsPresent) {
      headPresent = true;
      resolvedHeadConf = 0.80;
    } else if (headConfidence >= minHeadConfidence) {
      headPresent = true;
    }

    final bool facePresent = lipsPresent || headPresent;

    final result = FramePresenceResult(
      headPresent: headPresent,
      facePresent: facePresent,
      lipsPresent: lipsPresent,
      leftHandPresent: leftHandPresent,
      rightHandPresent: rightHandPresent,
      handConfidence: (rightHandPresent ? rightHandConfidence : 0.0) >
              (leftHandPresent ? leftHandConfidence : 0.0)
          ? rightHandConfidence
          : leftHandConfidence,
      headConfidence: resolvedHeadConf,
    );

    if (result.isSignEligible) {
      _consecutiveValidPresenceFrames++;
      _consecutiveMissingHandFrames = 0;
      _consecutiveMissingHeadFrames = 0;
    } else {
      _consecutiveValidPresenceFrames = 0;
      if (!result.hasAtLeastOneHand) {
        _consecutiveMissingHandFrames++;
      }
      if (!result.hasHeadOrFace) {
        _consecutiveMissingHeadFrames++;
      }
    }

    return result;
  }

  /// إعادة تعيين العدادات
  void reset() {
    _consecutiveValidPresenceFrames = 0;
    _consecutiveMissingHandFrames = 0;
    _consecutiveMissingHeadFrames = 0;
  }

  static bool _isLandmarkGroupValid(List<List<double>>? points, int expectedCount) {
    if (points == null || points.length < expectedCount) return false;
    int nonZero = 0;
    for (int i = 0; i < expectedCount; i++) {
      if (!_isZeroPoint(points[i])) nonZero++;
    }
    return nonZero >= (expectedCount * 0.5).toInt();
  }

  static bool _isZeroPoint(List<double> pt) {
    if (pt.length < 2) return true;
    return pt[0].abs() < 1e-6 && pt[1].abs() < 1e-6;
  }
}
