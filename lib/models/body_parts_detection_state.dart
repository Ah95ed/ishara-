import 'dart:ui';
import 'package:ishara/keypoints/ishara_keypoint_mapper.dart';
import 'package:ishara/keypoints/keypoint_validator.dart';
import 'package:ishara/ml/analyzer/ishara_sequence_quality_analyzer.dart';
import 'package:ishara/ml/buffer/ishara_frame_ring_buffer.dart';
import 'package:ishara/ml/model/ishara_tflite_service.dart';
import 'package:ishara/ml/preprocessing/ishara_model_input_validator.dart';
import 'package:ishara/ml/preprocessing/ishara_normalizer.dart';

/// حالات الكشف الثلاث
enum DetectionStatus {
  pass, // ✅ كامل
  partial, // ⚠️ جزئي
  fail, // ❌ غير موجود
}

/// نقطة معلم يد فردية (0..20)
class HandLandmarkPoint {
  final int index;
  final double x; // إحداثي طبيعي 0..1
  final double y; // إحداثي طبيعي 0..1
  final double z; // العمق النسبي

  const HandLandmarkPoint({
    required this.index,
    required this.x,
    required this.y,
    this.z = 0.0,
  });
}

/// نقطة ثنائية الأبعاد مطبعة 0..1
class NormalizedPoint {
  final double x;
  final double y;

  const NormalizedPoint(this.x, this.y);
}

/// نقطة معلم وضعية الجسم/الرأس
class PoseLandmarkPoint {
  final int index;
  final double x;
  final double y;
  final double likelihood;

  const PoseLandmarkPoint({
    required this.index,
    required this.x,
    required this.y,
    this.likelihood = 1.0,
  });
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
/// بالإضافة إلى إحداثيات المعالم الحية (Raw Live Landmarks) للرسم الفوري ومؤشرات التشخيص الحية.
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

  // ── إحداثيات المعالم الحقيقية اللحظية (Live Raw Landmarks) ──
  final List<HandLandmarkPoint>? rightHandPoints; // 21 نقطة
  final List<HandLandmarkPoint>? leftHandPoints;  // 21 نقطة
  final List<NormalizedPoint>? lipPoints;        // 19 نقطة
  final List<NormalizedPoint>? facePoints;       // نقاط شبكة الوجه
  final List<PoseLandmarkPoint>? posePoints;     // نقاط وضعية الجسم والرأس

  // ── نقاط المعايرة الفردية الدقيقة (Anchor Calibration Landmarks) ──
  final NormalizedPoint? noseTipPoint;        // Index 1 (Nose Tip)
  final NormalizedPoint? leftEyePoint;         // Index 33 (Left Eye Outer)
  final NormalizedPoint? rightEyePoint;        // Index 263 (Right Eye Outer)
  final NormalizedPoint? upperLipCenterPoint;  // Index 0 (Upper Lip Top)
  final NormalizedPoint? lowerLipCenterPoint;  // Index 17 (Lower Lip Bottom)
  final NormalizedPoint? chinPoint;            // Index 152 (Chin)

  // ── معلومات أبعاد الإطار ومطابقة التحويل الهندسي ──
  final Size sourceImageSize; // e.g. Size(480, 640)
  final int rotationDegrees;  // e.g. 270
  final bool isFrontCamera;
  final bool isMirrored;

  // ── تشخيص البث وحالة الحركة وتجمد البيانات ──
  final int frameId;
  final int detectorResultId;
  final DateTime? timestamp;
  final int landmarkAgeMs;
  final double motionDelta;
  final bool isPossiblyFrozen;

  // ── طبقة معالم الموديل الـ 86 والتحقق منها (Model Keypoints Layer) ──
  final KeypointFrame? rawKeypointFrame;
  final KeypointFrame? normalizedKeypointFrame;
  final KeypointValidationResult? keypointValidation;
  final FullNormalizedFrameResult? fullNormalizedResult;
  final ModelInputValidationReport? modelInputReport;
  final RingBufferStatus? ringBufferStatus;
  final ModelPipelineStatus? modelPipelineStatus;

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
    this.rightHandPoints,
    this.leftHandPoints,
    this.lipPoints,
    this.facePoints,
    this.posePoints,
    this.noseTipPoint,
    this.leftEyePoint,
    this.rightEyePoint,
    this.upperLipCenterPoint,
    this.lowerLipCenterPoint,
    this.chinPoint,
    this.sourceImageSize = const Size(480, 640),
    this.rotationDegrees = 270,
    this.isFrontCamera = true,
    this.isMirrored = true,
    this.frameId = 0,
    this.detectorResultId = 0,
    this.timestamp,
    this.landmarkAgeMs = 0,
    this.motionDelta = 0.0,
    this.isPossiblyFrozen = false,
    this.rawKeypointFrame,
    this.normalizedKeypointFrame,
    this.keypointValidation,
    this.fullNormalizedResult,
    this.modelInputReport,
    this.ringBufferStatus,
    this.modelPipelineStatus,
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
    rightHandPoints: null,
    leftHandPoints: null,
    lipPoints: null,
    facePoints: null,
    posePoints: null,
    noseTipPoint: null,
    leftEyePoint: null,
    rightEyePoint: null,
    upperLipCenterPoint: null,
    lowerLipCenterPoint: null,
    chinPoint: null,
    sourceImageSize: Size(480, 640),
    rotationDegrees: 270,
    isFrontCamera: true,
    isMirrored: true,
    frameId: 0,
    detectorResultId: 0,
    timestamp: null,
    landmarkAgeMs: 0,
    motionDelta: 0.0,
    isPossiblyFrozen: false,
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
        return '❌';
      case DetectionStatus.fail:
        return '❌';
    }
  }

  /// تقرير جودة تسلسل الـ 128 إطاراً الحالية
  SequenceQualityReport? get qualityReport => ringBufferStatus?.qualityReport;
}

