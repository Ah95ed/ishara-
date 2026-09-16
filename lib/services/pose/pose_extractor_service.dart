import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hand_detection/hand_detection.dart' as hd;
import 'package:ishara/services/person_presence_service.dart';
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
  final int handDetectorCalls;
  final int handDetectorResults;
  final int handDetectorErrors;
  final int leftHandResults;
  final int rightHandResults;
  final String? handDetectorException;
  final String? handDetectorStackTrace;

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
    this.handDetectorCalls = 0,
    this.handDetectorResults = 0,
    this.handDetectorErrors = 0,
    this.leftHandResults = 0,
    this.rightHandResults = 0,
    this.handDetectorException,
    this.handDetectorStackTrace,
  });
}

/// خدمة استخراج معالم الأيدي والوجه والجسم الـ 86 من إطارات الكاميرا
/// تراعي توجيه المستشعر، تدوير الكاميرا، والكاميرا الأمامية/الخلفية بدقة.
class PoseExtractorService {
  static const double _detectorConf = 0.45;
  static const double _minLandmarkScore = 0.35;
  static const int _maxDetections = 2;
  static const int _maxDim = 640;

  hd.HandDetector? _handDetector;
  final PersonPresenceService _personPresenceService = PersonPresenceService();
  bool _isInitialized = false;
  bool _isProcessing = false;

  int _handDetectorCalls = 0;
  int _handDetectorResults = 0;
  int _handDetectorErrors = 0;
  int _leftHandResults = 0;
  int _rightHandResults = 0;
  String? _lastHandDetectorError;
  String? _lastHandDetectorStackTrace;

  bool get isInitialized => _isInitialized;
  int get handDetectorCalls => _handDetectorCalls;
  int get handDetectorResults => _handDetectorResults;
  int get handDetectorErrors => _handDetectorErrors;
  int get leftHandResults => _leftHandResults;
  int get rightHandResults => _rightHandResults;
  String? get lastHandDetectorError => _lastHandDetectorError;
  String? get lastHandDetectorStackTrace => _lastHandDetectorStackTrace;

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
      await _personPresenceService.initialize();
      _isInitialized = true;
      debugPrint(
        '[PoseExtractorService] ✅ Hand detector initialized successfully',
      );
      debugPrint(
        '[PoseExtractorService] ✅ ML Kit pose detector initialized successfully',
      );
      return true;
    } catch (e, stack) {
      _isInitialized = false;
      _lastHandDetectorError = '$e';
      _lastHandDetectorStackTrace = '$stack';
      debugPrint(
        '[PoseExtractorService] ❌ Failed to initialize hand detector: $e\n$stack',
      );
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
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) {
        return ExtractedPoseFrame(
          hasActiveDetection: false,
          handDetectorErrors: ++_handDetectorErrors,
          handDetectorException: _lastHandDetectorError,
          handDetectorStackTrace: _lastHandDetectorStackTrace,
        );
      }
    }

    if (_isProcessing) {
      return ExtractedPoseFrame(
        hasActiveDetection: false,
        handDetectorCalls: _handDetectorCalls,
        handDetectorResults: _handDetectorResults,
        handDetectorErrors: _handDetectorErrors,
        leftHandResults: _leftHandResults,
        rightHandResults: _rightHandResults,
      );
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

      _handDetectorCalls++;
      List<hd.Hand> hands = const [];
      String? handError;
      String? handStack;

      try {
        hands = await _handDetector!.detectFromCameraImage(
          image,
          rotation: rotation,
          isBgra: Platform.isMacOS,
          maxDim: _maxDim,
        );
        _handDetectorResults++;
      } catch (e, stack) {
        _handDetectorErrors++;
        handError = e.toString();
        handStack = stack.toString();
        _lastHandDetectorError = handError;
        _lastHandDetectorStackTrace = handStack;
        debugPrint('[PoseExtractorService] ❌ Hand Detector Exception: $e');
      }

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
            _rightHandResults++;
          } else if (!isRightHand && leftHandPoints == null) {
            leftHandPoints = points;
            leftHandConf = hand.score.clamp(0.0, 1.0);
            _leftHandResults++;
          } else if (rightHandPoints == null) {
            rightHandPoints = points;
            rightHandConf = hand.score.clamp(0.0, 1.0);
            _rightHandResults++;
          } else if (leftHandPoints == null) {
            leftHandPoints = points;
            leftHandConf = hand.score.clamp(0.0, 1.0);
            _leftHandResults++;
          }
        }
      }

      final bool handPresent =
          rightHandPoints != null || leftHandPoints != null;

      debugPrint('HAND DETECTOR CALLS = $_handDetectorCalls');
      debugPrint('HAND DETECTOR RESULTS = $_handDetectorResults');
      debugPrint('HAND DETECTOR ERRORS = $_handDetectorErrors');
      debugPrint('LEFT HAND LANDMARKS = ${leftHandPoints?.length ?? 0}');
      debugPrint('RIGHT HAND LANDMARKS = ${rightHandPoints?.length ?? 0}');
      if (handPresent) {
        debugPrint('HAND = true');
      }

      PersonPresenceResult personCheck = PersonPresenceResult.empty;
      try {
        personCheck = await _personPresenceService.detectFromCameraImage(
          image,
          sensorOrientation: sensorOrientation,
          isFrontCamera: isFrontCamera,
          deviceOrientation: deviceOrientation,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[PoseExtractorService] ⚠️ PersonPresenceService error: $e');
        }
      }

      final bool bodyPosePresent =
          personCheck.posePresent || faceHeadResult.bodyPosePresent;
      final bool headPresent = personCheck.headPresent || faceHeadResult.headPresent;
      final bool facePresent = personCheck.facePresent || faceHeadResult.facePresent;
      final bool lipsPresent = personCheck.lipsPresent || faceHeadResult.lipsPresent;
      final bool personPresent = bodyPosePresent || headPresent || facePresent;
      final bool hasActiveDetection = handPresent && personPresent;

      // أسبقية معالم الجسم العلوي والشفاه من كاشف الوضعية المباشر
      final bodyPoints = personCheck.bodyPoints ?? faceHeadResult.headKeypoints;
      final lipPoints = personCheck.lipPoints ?? faceHeadResult.lipKeypoints;

      return ExtractedPoseFrame(
        rightHand: rightHandPoints,
        leftHand: leftHandPoints,
        lips: lipPoints,
        body: bodyPoints,
        hasActiveDetection: hasActiveDetection,
        personPresent: personPresent,
        bodyPosePresent: bodyPosePresent,
        headPresent: headPresent,
        facePresent: facePresent,
        lipsPresent: lipsPresent,
        handPresent: handPresent,
        rightHandConfidence: rightHandConf,
        leftHandConfidence: leftHandConf,
        headConfidence: personCheck.personPresent ? personCheck.bestConfidence : faceHeadResult.confidence,
        handDetectorCalls: _handDetectorCalls,
        handDetectorResults: _handDetectorResults,
        handDetectorErrors: _handDetectorErrors,
        leftHandResults: _leftHandResults,
        rightHandResults: _rightHandResults,
        handDetectorException: handError,
        handDetectorStackTrace: handStack,
      );
    } catch (e) {
      debugPrint('[PoseExtractorService] Error during extraction: $e');
      return ExtractedPoseFrame(
        hasActiveDetection: false,
        handDetectorCalls: _handDetectorCalls,
        handDetectorResults: _handDetectorResults,
        handDetectorErrors: ++_handDetectorErrors,
        handDetectorException: e.toString(),
      );
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
    await _personPresenceService.dispose();
    _handDetector = null;
    _isInitialized = false;
  }
}
