import 'dart:math' as math;
import 'package:ishara/keypoints/ishara_keypoint_mapper.dart';

/// نتيجة التحقق من صحة إطار النقاط الـ 86
class KeypointValidationResult {
  final int validCount; // 0..86
  final int missingCount; // 0..86
  final int nanCount;
  final int infCount;
  final bool hasInvalidNumbers;
  final bool isTrainingMappingVerified;

  // إحصائيات الحركة بين الإطارات
  final int movingPointsCount; // عدد النقاط التي تحركت فوق العتبة
  final double totalMovementDistance;
  final double averageMovementDistance;

  // تفاصيل كل جزء
  final int validRightHandPoints; // 0..21
  final int validLeftHandPoints; // 0..21
  final int validFaceLipPoints; // 0..19
  final int validBodyHeadPoints; // 0..25

  const KeypointValidationResult({
    required this.validCount,
    required this.missingCount,
    required this.nanCount,
    required this.infCount,
    required this.hasInvalidNumbers,
    required this.isTrainingMappingVerified,
    required this.movingPointsCount,
    required this.totalMovementDistance,
    required this.averageMovementDistance,
    required this.validRightHandPoints,
    required this.validLeftHandPoints,
    required this.validFaceLipPoints,
    required this.validBodyHeadPoints,
  });

  bool get isFullyDetected => validCount >= 86 && !hasInvalidNumbers;
}

/// KeypointValidator
/// مدقق ومحلل النقاط الصارم:
/// يرفض NaN و Infinity و -Infinity
/// يحسب النقاط الحقيقية الموجودة فقط ولا يخدع النظام بقيم صفرية وهمية
/// يقيس الحركة اللحظية لكل نقطة بين الإطارات لاكتشاف التغير والتجمد
class KeypointValidator {
  static const double motionThreshold = 0.004; // عتبة الحركة الطبيعية

  static KeypointValidationResult validate(
    KeypointFrame currentFrame, {
    KeypointFrame? previousFrame,
    double threshold = motionThreshold,
  }) {
    int valid = 0;
    int missing = 0;
    int nans = 0;
    int infs = 0;

    int rightHandValid = 0;
    int leftHandValid = 0;
    int faceLipsValid = 0;
    int bodyHeadValid = 0;

    int movingCount = 0;
    double totalDist = 0.0;
    int comparedPoints = 0;

    final currKps = currentFrame.keypoints;
    final prevKps = previousFrame?.keypoints;

    for (int i = 0; i < currKps.length; i++) {
      final kp = currKps[i];

      if (kp.isNaN) {
        nans++;
      } else if (kp.isInfinite) {
        infs++;
      } else if (kp.isValid) {
        valid++;

        switch (kp.source) {
          case ModelKeypointSource.rightHand:
            rightHandValid++;
            break;
          case ModelKeypointSource.leftHand:
            leftHandValid++;
            break;
          case ModelKeypointSource.faceLips:
            faceLipsValid++;
            break;
          case ModelKeypointSource.bodyHead:
            bodyHeadValid++;
            break;
        }

        // قياس الحركة مقارنة بالإطار السابق
        if (prevKps != null && i < prevKps.length && prevKps[i].isValid) {
          final double dx = kp.x! - prevKps[i].x!;
          final double dy = kp.y! - prevKps[i].y!;
          final double dist = math.sqrt(dx * dx + dy * dy);
          totalDist += dist;
          comparedPoints++;

          if (dist >= threshold) {
            movingCount++;
          }
        }
      } else {
        missing++;
      }
    }

    final double avgDist = comparedPoints > 0 ? totalDist / comparedPoints : 0.0;

    return KeypointValidationResult(
      validCount: valid,
      missingCount: missing,
      nanCount: nans,
      infCount: infs,
      hasInvalidNumbers: (nans > 0 || infs > 0),
      isTrainingMappingVerified: currentFrame.isTrainingMappingVerified,
      movingPointsCount: movingCount,
      totalMovementDistance: totalDist,
      averageMovementDistance: avgDist,
      validRightHandPoints: rightHandValid,
      validLeftHandPoints: leftHandValid,
      validFaceLipPoints: faceLipsValid,
      validBodyHeadPoints: bodyHeadValid,
    );
  }
}
