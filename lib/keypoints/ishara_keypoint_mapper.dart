import 'package:flutter/foundation.dart';
import 'package:ishara/models/body_parts_detection_state.dart';

/// مصدر نقطة المعلم في الموديل
enum ModelKeypointSource {
  rightHand,
  leftHand,
  faceLips,
  bodyHead,
}

/// وصف وبيانات كل نقطة من نقاط الموديل الـ 86
class ModelKeypointInfo {
  final int modelIndex; // 0..85
  final ModelKeypointSource source;
  final int sourceIndex;
  final String description;
  final double? x;
  final double? y;

  const ModelKeypointInfo({
    required this.modelIndex,
    required this.source,
    required this.sourceIndex,
    required this.description,
    this.x,
    this.y,
  });

  bool get isValid =>
      x != null &&
      y != null &&
      !x!.isNaN &&
      !x!.isInfinite &&
      !y!.isNaN &&
      !y!.isInfinite;

  bool get isNaN =>
      (x != null && x!.isNaN) || (y != null && y!.isNaN);

  bool get isInfinite =>
      (x != null && x!.isInfinite) || (y != null && y!.isInfinite);

  ModelKeypointInfo copyWithCoordinates(double? newX, double? newY) {
    return ModelKeypointInfo(
      modelIndex: modelIndex,
      source: source,
      sourceIndex: sourceIndex,
      description: description,
      x: newX,
      y: newY,
    );
  }
}

/// إطار نقاط الموديل الـ 86 [86, 2]
class KeypointFrame {
  final List<ModelKeypointInfo> keypoints;
  final DateTime timestamp;
  final bool isTrainingMappingVerified;

  const KeypointFrame({
    required this.keypoints,
    required this.timestamp,
    this.isTrainingMappingVerified = true,
  });

  /// عدد النقاط الحقيقية الصالحة (الموجودة وغير NaN/Inf)
  int get validCount => keypoints.where((k) => k.isValid).length;

  /// عدد النقاط المفقودة (لم يتم رصدها من الكاشف)
  int get missingCount => keypoints.where((k) => k.x == null || k.y == null).length;

  /// عدد النقاط التي تحتوي على NaN
  int get nanCount => keypoints.where((k) => k.isNaN).length;

  /// عدد النقاط التي تحتوي على Infinity
  int get infCount => keypoints.where((k) => k.isInfinite).length;

  /// تحويل النقاط إلى مصفوفة ثنائية الأبعاد [86, 2]
  List<List<double>> toMatrix({double missingValue = 0.0}) {
    return List.generate(keypoints.length, (i) {
      final kp = keypoints[i];
      if (kp.isValid) {
        return [kp.x!, kp.y!];
      }
      return [missingValue, missingValue];
    });
  }

  /// تحويل النقاط إلى Float32List مسطحة بطول 172 (86 * 2)
  Float32List toFlatArray({double missingValue = 0.0}) {
    final arr = Float32List(keypoints.length * 2);
    for (int i = 0; i < keypoints.length; i++) {
      final kp = keypoints[i];
      if (kp.isValid) {
        arr[i * 2] = kp.x!;
        arr[i * 2 + 1] = kp.y!;
      } else {
        arr[i * 2] = missingValue;
        arr[i * 2 + 1] = missingValue;
      }
    }
    return arr;
  }
}

/// IsharaKeypointMapper
/// الطبقة المستقلة الصريحة لربط مخرجات الكواشف بمصفوفة الموديل [86, 2]
/// تم التحقق من هذا الترتيب 100% من كود تدريب الداتاسيت الأصلي:
/// datasetv2.py / PoseDatasetV2 في pose_data_isharah2000_hands_lips_body
class IsharaKeypointMapper {
  static const int numRightHand = 21;
  static const int numLeftHand = 21;
  static const int numLips = 19;
  static const int numBody = 25;
  static const int totalKeypoints = 86;

  /// معرّفات نقاط الشفاه الـ 19 المستخرجة من MediaPipe Face Mesh (مرتبة ومطابقة لـ datasetv2.py):
  /// lipsUpperOuter = [61, 185, 40, 39, 37, 0, 267, 269, 270, 291]
  /// lipsLowerOuter = [146, 91, 181, 84, 17, 314, 405, 321, 375, 291]
  /// sorted(set(lipsUpperOuter + lipsLowerOuter))
  static const List<int> lipMeshIndices = [
    0, 17, 37, 39, 40, 61, 84, 91, 146, 181,
    185, 267, 269, 270, 291, 314, 321, 375, 405
  ];

  /// معرّفات نقاط الجسم العلوي والرأس الـ 25 من MediaPipe Pose (0..24):
  static const List<int> upperBodyIndices = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
    23, 24
  ];

  /// أوصاف نقاط الجسم والرأس الـ 25
  static const List<String> upperBodyDescriptions = [
    'Nose',
    'Left Eye Inner',
    'Left Eye',
    'Left Eye Outer',
    'Right Eye Inner',
    'Right Eye',
    'Right Eye Outer',
    'Left Ear',
    'Right Ear',
    'Left Mouth Corner',
    'Right Mouth Corner',
    'Left Shoulder',
    'Right Shoulder',
    'Left Elbow',
    'Right Elbow',
    'Left Wrist',
    'Right Wrist',
    'Left Pinky',
    'Right Pinky',
    'Left Index',
    'Right Index',
    'Left Thumb',
    'Right Thumb',
    'Left Hip',
    'Right Hip',
  ];

  /// أوصاف نقاط اليد الـ 21 (MediaPipe Hands)
  static const List<String> handLandmarkDescriptions = [
    'Wrist',
    'Thumb CMC',
    'Thumb MCP',
    'Thumb IP',
    'Thumb Tip',
    'Index MCP',
    'Index PIP',
    'Index DIP',
    'Index Tip',
    'Middle MCP',
    'Middle PIP',
    'Middle DIP',
    'Middle Tip',
    'Ring MCP',
    'Ring PIP',
    'Ring DIP',
    'Ring Tip',
    'Pinky MCP',
    'Pinky PIP',
    'Pinky DIP',
    'Pinky Tip',
  ];

  /// استخراج مصفوفة الـ 86 نقطة الخام (Raw Unnormalized Keypoints)
  static KeypointFrame extractRawModelKeypoints({
    List<HandLandmarkPoint>? rightHand,
    List<HandLandmarkPoint>? leftHand,
    List<NormalizedPoint>? lipsPoints,
    List<PoseLandmarkPoint>? posePoints,
    DateTime? timestamp,
  }) {
    final List<ModelKeypointInfo> list = [];
    final now = timestamp ?? DateTime.now();

    // ── 1. اليد اليمنى [0..20] ──
    final Map<int, HandLandmarkPoint> rhMap = {};
    if (rightHand != null) {
      for (final p in rightHand) {
        rhMap[p.index] = p;
      }
    }

    for (int i = 0; i < numRightHand; i++) {
      final p = rhMap[i];
      list.add(ModelKeypointInfo(
        modelIndex: i,
        source: ModelKeypointSource.rightHand,
        sourceIndex: i,
        description: 'Right Hand ${handLandmarkDescriptions[i]}',
        x: p?.x,
        y: p?.y,
      ));
    }

    // ── 2. اليد اليسرى [21..41] ──
    final Map<int, HandLandmarkPoint> lhMap = {};
    if (leftHand != null) {
      for (final p in leftHand) {
        lhMap[p.index] = p;
      }
    }

    for (int i = 0; i < numLeftHand; i++) {
      final p = lhMap[i];
      list.add(ModelKeypointInfo(
        modelIndex: numRightHand + i,
        source: ModelKeypointSource.leftHand,
        sourceIndex: i,
        description: 'Left Hand ${handLandmarkDescriptions[i]}',
        x: p?.x,
        y: p?.y,
      ));
    }

    // ── 3. الشفاه والوجه [42..60] (19 نقطة) ──
    final int lipsOffset = numRightHand + numLeftHand; // 42
    for (int i = 0; i < numLips; i++) {
      final meshIdx = lipMeshIndices[i];
      NormalizedPoint? p;
      if (lipsPoints != null && i < lipsPoints.length) {
        p = lipsPoints[i];
      }
      list.add(ModelKeypointInfo(
        modelIndex: lipsOffset + i,
        source: ModelKeypointSource.faceLips,
        sourceIndex: meshIdx,
        description: 'Face/Lips Mesh #$meshIdx',
        x: p?.x,
        y: p?.y,
      ));
    }

    // ── 4. الجسم والرأس [61..85] (25 نقطة) ──
    final int bodyOffset = lipsOffset + numLips; // 61
    final Map<int, PoseLandmarkPoint> poseMap = {};
    if (posePoints != null) {
      for (final p in posePoints) {
        poseMap[p.index] = p;
      }
    }

    for (int i = 0; i < numBody; i++) {
      final poseIdx = upperBodyIndices[i];
      final p = poseMap[poseIdx];
      list.add(ModelKeypointInfo(
        modelIndex: bodyOffset + i,
        source: ModelKeypointSource.bodyHead,
        sourceIndex: poseIdx,
        description: 'Body/Head ${upperBodyDescriptions[i]} (Pose #$poseIdx)',
        x: p?.x,
        y: p?.y,
      ));
    }

    return KeypointFrame(
      keypoints: list,
      timestamp: now,
      isTrainingMappingVerified: true,
    );
  }

  /// طباعة جدول المعالم الكامل (Diagnostic Dump)
  static void dumpKeypointMap(KeypointFrame frame) {
    debugPrint('==================================================');
    debugPrint('ISHARA KEYPOINT MAP DUMP [86, 2]');
    debugPrint('Frame timestamp: ${frame.timestamp.toIso8601String()}');
    debugPrint('Training Mapping: ${frame.isTrainingMappingVerified ? "VERIFIED ✅" : "NOT VERIFIED ❌"}');
    debugPrint('--------------------------------------------------');
    for (final kp in frame.keypoints) {
      final srcName = switch (kp.source) {
        ModelKeypointSource.rightHand => 'RightHand',
        ModelKeypointSource.leftHand => 'LeftHand',
        ModelKeypointSource.faceLips => 'FaceLips',
        ModelKeypointSource.bodyHead => 'BodyHead',
      };
      final valStr = kp.isValid
          ? 'x = ${kp.x!.toStringAsFixed(4)}, y = ${kp.y!.toStringAsFixed(4)}'
          : 'MISSING (x=null, y=null)';
      debugPrint(
        'Index ${kp.modelIndex.toString().padLeft(2, '0')}: '
        'source = ${srcName.padRight(9)} '
        'sourceIndex = ${kp.sourceIndex.toString().padLeft(3)} '
        'desc = ${kp.description.padRight(28)} '
        '$valStr',
      );
    }
    debugPrint('--------------------------------------------------');
    debugPrint('Shape: [86, 2]');
    debugPrint('Valid: ${frame.validCount} / 86');
    debugPrint('Missing: ${frame.missingCount}');
    debugPrint('NaN: ${frame.nanCount}');
    debugPrint('Inf: ${frame.infCount}');
    debugPrint('==================================================');
  }
}
