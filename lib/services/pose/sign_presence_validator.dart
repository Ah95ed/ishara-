/// نتيجة تقييم حضور عناصر الجسم في الإطار
class FramePresenceResult {
  final bool personPresent;
  final bool bodyPosePresent;
  final bool headPresent;
  final bool facePresent;
  final bool lipsPresent;
  final bool leftHandPresent;
  final bool rightHandPresent;
  final double handConfidence;
  final double headConfidence;

  const FramePresenceResult({
    required this.personPresent,
    required this.bodyPosePresent,
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

  /// تحقق شرط: وجود شخص (الرأس أو الوجه أو وضعية الجسم)
  bool get hasPerson => personPresent;

  /// تحقق شرط: الرأس أو الوجه متواجد
  bool get hasHeadOrFace => headPresent || facePresent;

  /// الشرط الإلزامي للإشارة:
  /// وجود شخص موثوق AND وجود يد واحدة على الأقل
  bool get isSignEligible => personPresent && hasAtLeastOneHand;

  static const FramePresenceResult empty = FramePresenceResult(
    personPresent: false,
    bodyPosePresent: false,
    headPresent: false,
    facePresent: false,
    lipsPresent: false,
    leftHandPresent: false,
    rightHandPresent: false,
  );
}

/// كاشف ومتحقق الحضور الصارم (SignPresenceValidator)
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

  /// تقييم الحضور لإطار مفرد مع الفصل الصارم بين الشخص واليد والشفتين
  FramePresenceResult evaluatePresence({
    List<List<double>>? rightHand,
    List<List<double>>? leftHand,
    List<List<double>>? lips,
    List<List<double>>? body,
    double rightHandConfidence = 0.0,
    double leftHandConfidence = 0.0,
    double headConfidence = 0.0,
    bool bodyPosePresent = false,
    bool headPresentDirect = false,
    bool facePresentDirect = false,
    bool personPresentDirect = false,
  }) {
    final bool rightHandPresent =
        _isLandmarkGroupValid(rightHand, 21) &&
        rightHandConfidence >= minHandConfidence;

    final bool leftHandPresent =
        _isLandmarkGroupValid(leftHand, 21) &&
        leftHandConfidence >= minHandConfidence;

    final bool lipsPresent = _isLandmarkGroupValid(lips, 19);

    // فحص موثوقية نقاط الجزء العلوي للجسم (Nose: 0, Left Shoulder: 11, Right Shoulder: 12)
    bool resolvedBodyPose = bodyPosePresent;
    if (body != null && body.length >= 13) {
      final bool noseOk = !_isZeroPoint(body[0]);
      final bool leftShoulderOk = !_isZeroPoint(body[11]);
      final bool rightShoulderOk = !_isZeroPoint(body[12]);
      if (noseOk || (leftShoulderOk && rightShoulderOk)) {
        resolvedBodyPose = true;
      }
    }

    bool headPresent = headPresentDirect;
    double resolvedHeadConf = headConfidence;

    if (body != null && body.length >= 11) {
      int validHeadPoints = 0;
      for (int i = 0; i < 11; i++) {
        if (!_isZeroPoint(body[i])) {
          validHeadPoints++;
        }
      }
      if (validHeadPoints >= 3) {
        headPresent = true;
        resolvedHeadConf = (validHeadPoints / 11.0);
      }
    } else if (lipsPresent) {
      headPresent = true;
      resolvedHeadConf = 0.80;
    } else if (headConfidence >= minHeadConfidence) {
      headPresent = true;
    }

    final bool facePresent = facePresentDirect || lipsPresent || headPresent;

    // 1. تعريف وجود الشخص (Pose OR Head OR Face):
    final bool personPresent =
        personPresentDirect || resolvedBodyPose || headPresent || facePresent;

    final result = FramePresenceResult(
      personPresent: personPresent,
      bodyPosePresent: resolvedBodyPose,
      headPresent: headPresent,
      facePresent: facePresent,
      lipsPresent: lipsPresent,
      leftHandPresent: leftHandPresent,
      rightHandPresent: rightHandPresent,
      handConfidence:
          (rightHandPresent ? rightHandConfidence : 0.0) >
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
      if (!result.personPresent) {
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

  static bool _isLandmarkGroupValid(
    List<List<double>>? points,
    int expectedCount,
  ) {
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
