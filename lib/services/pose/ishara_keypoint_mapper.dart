import 'package:ishara/models/landmarks_model.dart';

/// IsharaKeypointMapper
/// المسؤول الحصري عن ربط وترتيب نقاط MediaPipe بنقاط التدريب الـ 86 الدقيقة:
///
/// التوثيق الشامل والتفصيلي للفهارس (Exact 86 Keypoints Specification):
/// ─────────────────────────────────────────────────────────────────────────────
/// 1. اليد اليمنى (Right Hand) - [0..20] (21 نقطة MediaPipe Hand Landmark):
///    0: Wrist (المعصم)
///    1: Thumb CMC,  2: Thumb MCP,  3: Thumb IP,  4: Thumb Tip (طرف الإبهام)
///    5: Index MCP,  6: Index PIP,  7: Index DIP, 8: Index Tip (طرف السبابة)
///    9: Middle MCP, 10: Middle PIP, 11: Middle DIP, 12: Middle Tip (طرف الوسطى)
///    13: Ring MCP,  14: Ring PIP,  15: Ring DIP, 16: Ring Tip (طرف البنصر)
///    17: Pinky MCP, 18: Pinky PIP, 19: Pinky DIP, 20: Pinky Tip (طرف الخنصر)
///
/// 2. اليد اليسرى (Left Hand) - [21..41] (21 نقطة MediaPipe Hand Landmark):
///    21: Wrist (المعصم الأيسر)
///    22..25: Thumb (الإبهام الأيسر: CMC, MCP, IP, Tip)
///    26..29: Index (السبابة اليسرى: MCP, PIP, DIP, Tip)
///    30..33: Middle (الوسطى اليسرى: MCP, PIP, DIP, Tip)
///    34..37: Ring (البنصر الأيسر: MCP, PIP, DIP, Tip)
///    38..41: Pinky (الخنصر الأيسر: MCP, PIP, DIP, Tip)
///
/// 3. الشفاه (Face Mesh Outer Lips Contour) - [42..60] (19 نقطة):
///    42: Mesh 0    (Top lip center)
///    43: Mesh 17   (Bottom lip center)
///    44..52: Mesh [37, 39, 40, 61, 84, 91, 146, 181, 185]
///    53..60: Mesh [267, 269, 270, 291, 314, 321, 375, 405]
///
/// 4. الجزء العلوي للجسم والرأس (MediaPipe Pose Upper Body) - [61..85] (25 نقطة):
///    61: 0 - Nose (الأنف / مركز الوجه والرأس)
///    62..64: 1, 2, 3 - Left Eye (Inner, Center, Outer)
///    65..67: 4, 5, 6 - Right Eye (Inner, Center, Outer)
///    68: 7 - Left Ear (الأذن اليسرى)
///    69: 8 - Right Ear (الأذن اليمنى)
///    70: 9 - Mouth Left (زاوية الفم اليسرى)
///    71: 10 - Mouth Right (زاوية الفم اليمنى)
///    72: 11 - Left Shoulder (الكتف الأيسر)
///    73: 12 - Right Shoulder (الكتف الأيمن)
///    74: 13 - Left Elbow (المرفق الأيسر)
///    75: 14 - Right Elbow (المرفق الأيمن)
///    76: 15 - Left Wrist (المعصم الأيسر في هيكل الجسم)
///    77: 16 - Right Wrist (المعصم الأيمن في هيكل الجسم)
///    78: 17 - Left Pinky,  79: 18 - Right Pinky
///    80: 19 - Left Index,  81: 20 - Right Index
///    82: 21 - Left Thumb,  83: 22 - Right Thumb
///    84: 23 - Left Hip (الورك الأيسر)
///    85: 24 - Right Hip (الورك الأيمن)
/// ─────────────────────────────────────────────────────────────────────────────
class IsharaKeypointMapper {
  static const int numRightHand = 21;
  static const int numLeftHand = 21;
  static const int numLips = 19;
  static const int numBody = 25;
  static const int totalKeypoints = 86;

  /// معرّفات نقاط الشفاه الخارجية المستخرجة من MediaPipe Face Mesh:
  static const List<int> lipMeshIndices = [
    0, 17, 37, 39, 40, 61, 84, 91, 146, 181,
    185, 267, 269, 270, 291, 314, 321, 375, 405
  ];

  /// معرّفات نقاط الجسم العلوي الـ 25 من MediaPipe Pose:
  static const List<int> upperBodyIndices = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
    23, 24
  ];

  /// تحويل كائنات المعالم إلى مصفوفة [86][2] خام قبل التطبيع
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

    // 4. خريطة الجسم العلوي والرأس [61..85] (25 نقطة)
    final int bodyOffset = lipsOffset + numLips; // 61
    if (bodyPoints != null && bodyPoints.length >= numBody) {
      for (int i = 0; i < numBody; i++) {
        frame[bodyOffset + i][0] = bodyPoints[i][0];
        frame[bodyOffset + i][1] = bodyPoints[i][1];
      }
    }

    return frame;
  }
}
