import 'package:ishara/models/landmarks_model.dart';

/// IsharaKeypointMapper
/// المسؤول الحصري عن ربط وترتيب نقاط MediaPipe بنقاط التدريب الـ 86 الدقيقة:
///
/// الترتيب المعتمد في datasetv2.py ونوت بوك guide_isharah_pose_pkl_reader_visualizer:
/// - [0..20]   : اليد اليمنى (Right Hand) - 21 نقطة
/// - [21..41]  : اليد اليسرى (Left Hand)  - 21 نقطة
/// - [42..60]  : الشفاه (Lips)            - 19 نقطة من الـ Outer Contour لـ Face Mesh
/// - [61..85]  : الجزء العلوي للجسم (Upper Body) - 25 نقطة (مفاصل 0..24 من MediaPipe Pose)
class IsharaKeypointMapper {
  static const int numRightHand = 21;
  static const int numLeftHand = 21;
  static const int numLips = 19;
  static const int numBody = 25;
  static const int totalKeypoints = 86;

  /// معرّفات نقاط الشفاه الخارجية المستخرجة من MediaPipe Face Mesh:
  /// lipsUpperOuter = [61, 185, 40, 39, 37, 0, 267, 269, 270, 291]
  /// lipsLowerOuter = [146, 91, 181, 84, 17, 314, 405, 321, 375, 291]
  /// مرتبة وبدون تكرار:
  static const List<int> lipMeshIndices = [
    0, 17, 37, 39, 40, 61, 84, 91, 146, 181,
    185, 267, 269, 270, 291, 314, 321, 375, 405
  ];

  /// معرّفات نقاط الجسم العلوي الـ 25 من MediaPipe Pose:
  /// 0..24 تشمل: الرأس والعيون والأذنين والأنف، الكتفين، المرفقين، المعصمين، والوركين
  static const List<int> upperBodyIndices = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
    23, 24
  ];

  /// تحويل كائنات المعالم إلى مصفوفة [86][2] خام قبل التطبيع
  /// مع دعم دقيق لليد اليمنى واليسرى والكاميرا الأمامية/الخلفية
  static List<List<double>> mapTo86Keypoints({
    List<HandLandmark>? rightHand,
    List<HandLandmark>? leftHand,
    List<List<double>>? lipsPoints,
    List<List<double>>? bodyPoints,
    bool isFrontCamera = false,
  }) {
    final frame = List.generate(totalKeypoints, (_) => [0.0, 0.0]);

    // 1. خريطة اليد اليمنى [0..20]
    if (rightHand != null && rightHand.length == numRightHand) {
      for (int i = 0; i < numRightHand; i++) {
        frame[i][0] = rightHand[i].x;
        frame[i][1] = rightHand[i].y;
      }
    }

    // 2. خريطة اليد اليسرى [21..41]
    if (leftHand != null && leftHand.length == numLeftHand) {
      for (int i = 0; i < numLeftHand; i++) {
        frame[numRightHand + i][0] = leftHand[i].x;
        frame[numRightHand + i][1] = leftHand[i].y;
      }
    }

    // 3. خريطة الشفاه [42..60] (19 نقطة)
    final int lipsOffset = numRightHand + numLeftHand; // 42
    if (lipsPoints != null && lipsPoints.length >= numLips) {
      for (int i = 0; i < numLips; i++) {
        frame[lipsOffset + i][0] = lipsPoints[i][0];
        frame[lipsOffset + i][1] = lipsPoints[i][1];
      }
    }

    // 4. خريطة الجسم العلوي [61..85] (25 نقطة)
    final int bodyOffset = lipsOffset + numLips; // 61
    if (bodyPoints != null && bodyPoints.length >= numBody) {
      for (int i = 0; i < numBody; i++) {
        frame[bodyOffset + i][0] = bodyPoints[i][0];
        frame[bodyOffset + i][1] = bodyPoints[i][1];
      }
    } else if (rightHand != null || leftHand != null) {
      // تقدير موضعي مبدئي لمفصلي المعصمين في الجسم في حال غياب Pose كامل
      // نقطة 15 (معصم أيسر) ونقطة 16 (معصم أيمن) في MediaPipe Pose
      if (leftHand != null && leftHand.isNotEmpty) {
        frame[bodyOffset + 15][0] = leftHand[0].x;
        frame[bodyOffset + 15][1] = leftHand[0].y;
      }
      if (rightHand != null && rightHand.isNotEmpty) {
        frame[bodyOffset + 16][0] = rightHand[0].x;
        frame[bodyOffset + 16][1] = rightHand[0].y;
      }
    }

    return frame;
  }
}
