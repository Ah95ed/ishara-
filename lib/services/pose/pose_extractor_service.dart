import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hand_detection/hand_detection.dart' as hd;
import 'package:ishara/services/pose/face_head_detector.dart';

/// نتيجة استخراج المعالم من إطار الكاميرا مع مؤشرات الحضور والثقة
class ExtractedPoseFrame {
  final List<List<double>>? rightHand;
  final List<List<double>>? leftHand;
  final List<List<double>>? lips;
  final List<List<double>>? body;
  final bool hasActiveDetection;
  final bool personPresent;
  final bool bodyPosePresent;
  final bool headPresent;
  final bool facePresent;
  final bool lipsPresent;
  final bool handPresent;
  final double rightHandConfidence;
  final double leftHandConfidence;
  final double headConfidence;

  const ExtractedPoseFrame({
    this.rightHand,
    this.leftHand,
    this.lips,
    this.body,
    required this.hasActiveDetection,
    this.personPresent = false,
    this.bodyPosePresent = false,
    this.headPresent = false,
    this.facePresent = false,
    this.lipsPresent = false,
    this.handPresent = false,
    this.rightHandConfidence = 0.0,
    this.leftHandConfidence = 0.0,
    this.headConfidence = 0.0,
  });
}

/// خدمة استخراج معالم الأيدي والوجه والجسم الـ 86 من إطارات الكاميرا
/// تراعي توجيه المستشعر، تدوير الكاميرا، والكاميرا الأمامية/الخلفية بدقة.
class PoseExtractorService {
  static const double _detectorConf = 0.65;
  static const double _minLandmarkScore = 0.40;
  static const int _maxDetections = 2;
  static const int _maxDim = 640;

  hd.HandDetector? _handDetector;
  bool _isInitialized = false;
  bool _isProcessing = false;

  bool get isInitialized => _isInitialized;

  /// تهيئة محرك الكشف
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _handDetector = await hd.HandDetector.create(
        mode: hd.HandMode.boxesAndLandmarks,
        detectorConf: _detectorConf,
        minLandmarkScore: _minLandmarkScore,
        maxDetections: _maxDetections,
        enableTracking: true,
        performanceConfig: hd.PerformanceConfig.xnnpack(numThreads: 2),
      );
      _isInitialized = true;
      debugPrint('[PoseExtractorService] ✅ Hand detector initialized successfully');
      return true;
    } catch (e) {
      _isInitialized = false;
      debugPrint('[PoseExtractorService] ❌ Failed to initialize hand detector: $e');
      return false;
    }
  }

  /// استخراج معالم الإطار من CameraImage مع كشف الرأس والوجه والأيدي
  Future<ExtractedPoseFrame> extractFromCameraImage(
    CameraImage image, {
    int? sensorOrientation,
    bool isFrontCamera = false,
    DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp,
  }) async {
    if (!_isInitialized || _handDetector == null || _isProcessing) {
      return const ExtractedPoseFrame(hasActiveDetection: false);
    }

    _isProcessing = true;
    try {
      // 1. كشف الرأس والوجه والجسم مع دعم كامل للتدوير
      final faceHeadResult = FaceHeadDetector.detectFromCameraImage(
        image,
        sensorOrientation: sensorOrientation,
        isFrontCamera: isFrontCamera,
        deviceOrientation: deviceOrientation,
      );

      // 2. كشف الأيدي عبر نموذج MediaPipe Hand
      final hd.CameraFrameRotation? rotation = sensorOrientation == null
          ? null
          : hd.rotationForFrame(
              width: image.width,
              height: image.height,
              sensorOrientation: sensorOrientation,
              isFrontCamera: isFrontCamera,
              deviceOrientation: deviceOrientation,
            );

      final Size detSize = hd.detectionSize(
        width: image.width,
        height: image.height,
        rotation: rotation,
        maxDim: _maxDim,
      );

      final List<hd.Hand> hands = await _handDetector!.detectFromCameraImage(
        image,
        rotation: rotation,
        isBgra: Platform.isMacOS,
        maxDim: _maxDim,
      );

      final double dW = detSize.width;
      final double dH = detSize.height;

      List<List<double>>? rightHandPoints;
      List<List<double>>? leftHandPoints;
      double rightHandConf = 0.0;
      double leftHandConf = 0.0;

      if (hands.isNotEmpty && dW > 0 && dH > 0) {
        for (final hand in hands) {
          if (!hand.hasLandmarks || hand.landmarks.length != 21) continue;

          // تحويل النقاط إلى إحداثيات نسبية [0..1]
          final points = <List<double>>[];
          for (int i = 0; i < 21; i++) {
            final lm = hand.landmarks[i];
            final double nx = (lm.x / dW).clamp(0.0, 1.0);
            final double ny = (lm.y / dH).clamp(0.0, 1.0);
            points.add([nx, ny]);
          }

          // ضبط دلالة اليد اليمنى واليسرى مع مراعاة مرآة الكاميرا الأمامية (المتطلب 15)
          final bool isRightHand;
          if (isFrontCamera) {
            // في الكاميرا الأمامية (Mirror mode): اليد اليسرى في الصورة تقابل اليد اليمنى للشخص
            isRightHand = hand.handedness == hd.Handedness.left;
          } else {
            isRightHand = hand.handedness == hd.Handedness.right;
          }

          if (isRightHand && rightHandPoints == null) {
            rightHandPoints = points;
            rightHandConf = hand.score.clamp(0.0, 1.0);
          } else if (!isRightHand && leftHandPoints == null) {
            leftHandPoints = points;
            leftHandConf = hand.score.clamp(0.0, 1.0);
          } else if (rightHandPoints == null) {
            rightHandPoints = points;
            rightHandConf = hand.score.clamp(0.0, 1.0);
          } else if (leftHandPoints == null) {
            leftHandPoints = points;
            leftHandConf = hand.score.clamp(0.0, 1.0);
          }
        }
      }

      final bool handPresent = rightHandPoints != null || leftHandPoints != null;
      final bool bodyPosePresent = faceHeadResult.bodyPosePresent;
      final bool headPresent = faceHeadResult.headPresent;
      final bool facePresent = faceHeadResult.facePresent;
      final bool lipsPresent = faceHeadResult.lipsPresent;
      final bool personPresent = bodyPosePresent || headPresent || facePresent;
      final bool hasActiveDetection = handPresent && personPresent;

      return ExtractedPoseFrame(
        rightHand: rightHandPoints,
        leftHand: leftHandPoints,
        lips: faceHeadResult.lipKeypoints,
        body: faceHeadResult.headKeypoints,
        hasActiveDetection: hasActiveDetection,
        personPresent: personPresent,
        bodyPosePresent: bodyPosePresent,
        headPresent: headPresent,
        facePresent: facePresent,
        lipsPresent: lipsPresent,
        handPresent: handPresent,
        rightHandConfidence: rightHandConf,
        leftHandConfidence: leftHandConf,
        headConfidence: faceHeadResult.confidence,
      );
    } catch (e) {
      debugPrint('[PoseExtractorService] Error during extraction: $e');
      return const ExtractedPoseFrame(hasActiveDetection: false);
    } finally {
      _isProcessing = false;
    }
  }

  void reset() {
    _isProcessing = false;
  }

  Future<void> dispose() async {
    try {
      await _handDetector?.dispose();
    } catch (_) {}
    _handDetector = null;
    _isInitialized = false;
  }
}
