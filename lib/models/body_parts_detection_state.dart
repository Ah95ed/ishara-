/// حالات الكشف الثلاث
enum DetectionStatus {
  pass, // ✅ كامل
  partial, // ⚠️ جزئي
  fail, // ❌ غير موجود
}

/// حالة كل جزء مع عدد النقاط الفعلي والمطلوب
class LandmarkPartStatus {
  final bool detected;
  final int actualPoints;
  final int requiredPoints;

  const LandmarkPartStatus({
    required this.detected,
    required this.actualPoints,
    required this.requiredPoints,
  });

  DetectionStatus get status {
    if (actualPoints >= requiredPoints && requiredPoints > 0) {
      return DetectionStatus.pass;
    } else if (actualPoints > 0) {
      return DetectionStatus.partial;
    } else {
      return DetectionStatus.fail;
    }
  }

  String get icon {
    switch (status) {
      case DetectionStatus.pass:
        return '✅';
      case DetectionStatus.partial:
        return '⚠️';
      case DetectionStatus.fail:
        return '❌';
    }
  }

  static const emptyHead = LandmarkPartStatus(detected: false, actualPoints: 0, requiredPoints: 11);
  static const emptyFace = LandmarkPartStatus(detected: false, actualPoints: 0, requiredPoints: 468);
  static const emptyLips = LandmarkPartStatus(detected: false, actualPoints: 0, requiredPoints: 19);
  static const emptyHand = LandmarkPartStatus(detected: false, actualPoints: 0, requiredPoints: 21);
}

/// VisionLandmarksState
/// نموذج الحالة الشامل الذي يحتوي على حالة ونقاط كل جزء والنقاط الـ 86 للموديل
class VisionLandmarksState {
  final bool personDetected;

  final LandmarkPartStatus head;
  final LandmarkPartStatus face;
  final LandmarkPartStatus lips;
  final LandmarkPartStatus rightHand;
  final LandmarkPartStatus leftHand;

  final int modelFaceLipPoints; // 0..19
  final int modelBodyHeadPoints; // 0..25
  final int totalModelPoints; // 0..86
  final double fps;

  const VisionLandmarksState({
    required this.personDetected,
    required this.head,
    required this.face,
    required this.lips,
    required this.rightHand,
    required this.leftHand,
    required this.modelFaceLipPoints,
    required this.modelBodyHeadPoints,
    required this.totalModelPoints,
    this.fps = 0.0,
  });

  static const empty = VisionLandmarksState(
    personDetected: false,
    head: LandmarkPartStatus.emptyHead,
    face: LandmarkPartStatus.emptyFace,
    lips: LandmarkPartStatus.emptyLips,
    rightHand: LandmarkPartStatus.emptyHand,
    leftHand: LandmarkPartStatus.emptyHand,
    modelFaceLipPoints: 0,
    modelBodyHeadPoints: 0,
    totalModelPoints: 0,
    fps: 0.0,
  );

  DetectionStatus get totalStatus {
    if (totalModelPoints >= 86) {
      return DetectionStatus.pass;
    } else if (totalModelPoints > 0) {
      return DetectionStatus.partial;
    } else {
      return DetectionStatus.fail;
    }
  }

  String get totalIcon {
    switch (totalStatus) {
      case DetectionStatus.pass:
        return '✅';
      case DetectionStatus.partial:
        return '❌'; // كما طلب المستخدم: إذا ناقصة اعرض ❌ X/86
      case DetectionStatus.fail:
        return '❌';
    }
  }
}
