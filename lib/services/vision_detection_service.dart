import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:hand_detection/hand_detection.dart' as hd;
import 'package:ishara/models/body_parts_detection_state.dart';

/// موازن الحالة المعتمد على عدد الإطارات (Frame-based Stabilizer)
/// يمنع التذبذب السريع بدون أي تأخير زمني مصطنع.
class PartStabilizer {
  final int framesToActivate;
  final int framesToDeactivate;
  int _consecutivePositives = 0;
  int _consecutiveNegatives = 0;
  bool _currentState = false;

  PartStabilizer({
    this.framesToActivate = 2,
    this.framesToDeactivate = 4,
  });

  bool update(bool rawState) {
    if (rawState) {
      _consecutiveNegatives = 0;
      _consecutivePositives++;
      if (_consecutivePositives >= framesToActivate) {
        _currentState = true;
      }
    } else {
      _consecutivePositives = 0;
      _consecutiveNegatives++;
      if (_consecutiveNegatives >= framesToDeactivate) {
        _currentState = false;
      }
    }
    return _currentState;
  }

  void reset() {
    _consecutivePositives = 0;
    _consecutiveNegatives = 0;
    _currentState = false;
  }
}

/// VisionDetectionService
/// الخدمة الموحدة المسؤولة عن معالجة إطارات الكاميرا
/// واستخراج حالة وعدد النقاط الحقيقية لكل جزء ونقاط الموديل الـ 86.
class VisionDetectionService {
  PoseDetector? _poseDetector;
  FaceMeshDetector? _faceMeshDetector;
  hd.HandDetector? _handDetector;

  bool _isInitialized = false;
  bool _isProcessing = false;

  // ── الفهارس الحقيقية لنقاط الموديل الـ 86 ──
  /// نقاط الشفاه الخارجية الـ 19 المستخرجة من MediaPipe Face Mesh:
  static const List<int> lipMeshIndices = [
    0, 17, 37, 39, 40, 61, 84, 91, 146, 181,
    185, 267, 269, 270, 291, 314, 321, 375, 405
  ];

  /// معالم الرأس الـ 11 في MediaPipe Pose (الفهارس 0..10):
  static const List<PoseLandmarkType> headPoseTypes = [
    PoseLandmarkType.nose,           // 0
    PoseLandmarkType.leftEyeInner,   // 1
    PoseLandmarkType.leftEye,        // 2
    PoseLandmarkType.leftEyeOuter,   // 3
    PoseLandmarkType.rightEyeInner,  // 4
    PoseLandmarkType.rightEye,       // 5
    PoseLandmarkType.rightEyeOuter,  // 6
    PoseLandmarkType.leftEar,        // 7
    PoseLandmarkType.rightEar,       // 8
    PoseLandmarkType.leftMouth,      // 9
    PoseLandmarkType.rightMouth,     // 10
  ];

  /// معالم الجزء العلوي للجسم الـ 14 في MediaPipe Pose (الفهارس 11..24):
  static const List<PoseLandmarkType> upperBodyPoseTypes = [
    PoseLandmarkType.leftShoulder,   // 11
    PoseLandmarkType.rightShoulder,  // 12
    PoseLandmarkType.leftElbow,      // 13
    PoseLandmarkType.rightElbow,     // 14
    PoseLandmarkType.leftWrist,      // 15
    PoseLandmarkType.rightWrist,     // 16
    PoseLandmarkType.leftPinky,      // 17
    PoseLandmarkType.rightPinky,     // 18
    PoseLandmarkType.leftIndex,      // 19
    PoseLandmarkType.rightIndex,     // 20
    PoseLandmarkType.leftThumb,      // 21
    PoseLandmarkType.rightThumb,     // 22
    PoseLandmarkType.leftHip,        // 23
    PoseLandmarkType.rightHip,       // 24
  ];

  // موازنات الاستقرار الـ 6
  final PartStabilizer _personStabilizer = PartStabilizer(framesToActivate: 2, framesToDeactivate: 4);
  final PartStabilizer _headStabilizer = PartStabilizer(framesToActivate: 2, framesToDeactivate: 4);
  final PartStabilizer _faceStabilizer = PartStabilizer(framesToActivate: 2, framesToDeactivate: 4);
  final PartStabilizer _lipsStabilizer = PartStabilizer(framesToActivate: 2, framesToDeactivate: 4);
  final PartStabilizer _leftHandStabilizer = PartStabilizer(framesToActivate: 2, framesToDeactivate: 4);
  final PartStabilizer _rightHandStabilizer = PartStabilizer(framesToActivate: 2, framesToDeactivate: 4);

  // إحصائيات الأداء ومعدل الفريمات
  int _fpsFrameCounter = 0;
  DateTime? _lastFpsCalcTime;
  double _currentFps = 0.0;
  DateTime? _lastProcessedFrameTime;

  bool get isInitialized => _isInitialized;

  /// تهيئة المحركات الثلاثة دفعة واحدة
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. كاشف وضعية الجسم والرأس (Google ML Kit Pose Detection - Stream Mode)
      _poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          model: PoseDetectionModel.base,
          mode: PoseDetectionMode.stream,
        ),
      );

      // 2. كاشف الوجه والشفاه الحقيقية (MediaPipe Face Mesh 468 points)
      _faceMeshDetector = FaceMeshDetector(
        option: FaceMeshDetectorOptions.faceMesh,
      );

      // 3. كاشف الأيدي المزدوج (MediaPipe Hands - 21 points each)
      _handDetector = await hd.HandDetector.create(
        mode: hd.HandMode.boxesAndLandmarks,
        detectorConf: 0.50,
        minLandmarkScore: 0.35,
        maxDetections: 2,
        enableTracking: true,
        performanceConfig: hd.PerformanceConfig.xnnpack(numThreads: 2),
      );

      _isInitialized = true;
      debugPrint('[VisionDetectionService] ✅ Initialized all 3 Vision Detectors successfully.');
    } catch (e, stack) {
      _isInitialized = false;
      debugPrint('[VisionDetectionService] ❌ Initialization failed: $e\n$stack');
    }
  }

  /// معالجة إطار الكاميرا وحساب النقاط الفعلية لكل جزء
  Future<VisionLandmarksState?> processFrame(
    CameraImage image, {
    int? sensorOrientation,
    bool isFrontCamera = true,
    DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp,
  }) async {
    if (!_isInitialized || _isProcessing) return null;

    // خفض الفريمات لمنع تراكم الطوابير (15-18 FPS)
    final now = DateTime.now();
    if (_lastProcessedFrameTime != null) {
      final elapsedMs = now.difference(_lastProcessedFrameTime!).inMilliseconds;
      if (elapsedMs < 55) {
        return null;
      }
    }

    _isProcessing = true;
    _lastProcessedFrameTime = now;

    try {
      _calcFps();

      // بناء InputImage المشترك لـ Pose و FaceMesh
      final inputImage = _createInputImage(
        image,
        sensorOrientation: sensorOrientation,
        isFrontCamera: isFrontCamera,
        deviceOrientation: deviceOrientation,
      );

      // حساب زاوية دوران اليدين
      final hd.CameraFrameRotation? handRotation = sensorOrientation == null
          ? null
          : hd.rotationForFrame(
              width: image.width,
              height: image.height,
              sensorOrientation: sensorOrientation,
              isFrontCamera: isFrontCamera,
              deviceOrientation: deviceOrientation,
            );

      // تشغيل الكواشف الثلاثة على نفس الإطار بالتوازي
      final List<dynamic> results = await Future.wait([
        inputImage != null ? _poseDetector!.processImage(inputImage) : Future.value(<Pose>[]),
        inputImage != null ? _faceMeshDetector!.processImage(inputImage) : Future.value(<FaceMesh>[]),
        _handDetector != null
            ? _handDetector!.detectFromCameraImage(
                image,
                rotation: handRotation,
                isBgra: Platform.isMacOS,
                maxDim: 640,
              )
            : Future.value(<hd.Hand>[]),
      ]);

      final List<Pose> poses = results[0] as List<Pose>;
      final List<FaceMesh> faceMeshes = results[1] as List<FaceMesh>;
      final List<hd.Hand> hands = results[2] as List<hd.Hand>;

      // ── 1. حساب نقاط الرأس والجسم من Pose Detector ──
      int actualHeadPoints = 0;
      int actualUpperBodyPoints = 0;

      if (poses.isNotEmpty) {
        final pose = poses.first;
        final landmarks = pose.landmarks;

        // فحص معالم الرأس الـ 11
        for (final type in headPoseTypes) {
          final lm = landmarks[type];
          if (lm != null && lm.likelihood >= 0.35) {
            actualHeadPoints++;
          }
        }

        // فحص معالم الجسم العلوي الـ 14
        for (final type in upperBodyPoseTypes) {
          final lm = landmarks[type];
          if (lm != null && lm.likelihood >= 0.35) {
            actualUpperBodyPoints++;
          }
        }
      }

      // إجمالي نقاط Body/Head للموديل (11 + 14 = 25)
      final int actualModelBodyHeadPoints = actualHeadPoints + actualUpperBodyPoints;

      // ── 2. حساب نقاط الوجه والشفاه من Face Mesh ──
      int actualFacePoints = 0;
      int actualModelFaceLipPoints = 0;

      if (faceMeshes.isNotEmpty) {
        final mesh = faceMeshes.first;
        actualFacePoints = mesh.points.length; // 468 نقطة حقيقية

        // فحص معالم الشفاه الـ 19 من Mesh points
        final Set<int> availableMeshIndices = mesh.points.map((p) => p.index).toSet();
        for (final idx in lipMeshIndices) {
          if (availableMeshIndices.contains(idx)) {
            actualModelFaceLipPoints++;
          }
        }
      }

      // ── 3. حساب نقاط اليد اليمنى واليسرى من MediaPipe Hands ──
      int actualRightHandPoints = 0;
      int actualLeftHandPoints = 0;

      for (final hand in hands) {
        if (hand.hasLandmarks) {
          final int count = hand.landmarks.length.clamp(0, 21);
          if (hand.handedness == hd.Handedness.right) {
            actualRightHandPoints = count;
          } else if (hand.handedness == hd.Handedness.left) {
            actualLeftHandPoints = count;
          }
        }
      }

      // ── 4. حساب إجمالي نقاط الموديل الـ 86 الفعلية ──
      // ممنوع جمع 21+21+19+25 ثابتاً — الحساب ناتج من النقاط الحقيقية المكتشفة فقط
      final int actualTotalModelPoints = actualRightHandPoints +
          actualLeftHandPoints +
          actualModelFaceLipPoints +
          actualModelBodyHeadPoints;

      // ── 5. كشف الشخص (وجود جسم OR رأس OR وجه — دون اشتراط اليد إطلاقاً) ──
      final bool rawPerson = (actualUpperBodyPoints > 0) ||
          (actualHeadPoints >= 2) ||
          (actualFacePoints >= 30);

      // تطبيق موازنات الاستقرار
      final bool personDetected = _personStabilizer.update(rawPerson);
      final bool headDetected = _headStabilizer.update(actualHeadPoints >= 2);
      final bool faceDetected = _faceStabilizer.update(actualFacePoints >= 30);
      final bool lipsDetected = _lipsStabilizer.update(actualModelFaceLipPoints >= 10);
      final bool rightHandDetected = _rightHandStabilizer.update(actualRightHandPoints >= 10);
      final bool leftHandDetected = _leftHandStabilizer.update(actualLeftHandPoints >= 10);

      // ── طباعة الـ Console المطلوبة بحذافيرها ──
      debugPrint('========================================');
      debugPrint('PERSON=$personDetected');
      debugPrint('HEAD=$actualHeadPoints/11');
      debugPrint('FACE=$actualFacePoints/468');
      debugPrint('LIPS=$actualModelFaceLipPoints/19');
      debugPrint('RIGHT_HAND=$actualRightHandPoints/21');
      debugPrint('LEFT_HAND=$actualLeftHandPoints/21');
      debugPrint('MODEL_FACE_LIPS=$actualModelFaceLipPoints/19');
      debugPrint('MODEL_BODY_HEAD=$actualModelBodyHeadPoints/25');
      debugPrint('TOTAL=$actualTotalModelPoints/86');
      debugPrint('========================================');

      return VisionLandmarksState(
        personDetected: personDetected,
        head: LandmarkPartStatus(
          detected: headDetected,
          actualPoints: actualHeadPoints,
          requiredPoints: 11,
        ),
        face: LandmarkPartStatus(
          detected: faceDetected,
          actualPoints: actualFacePoints,
          requiredPoints: 468,
        ),
        lips: LandmarkPartStatus(
          detected: lipsDetected,
          actualPoints: actualModelFaceLipPoints,
          requiredPoints: 19,
        ),
        rightHand: LandmarkPartStatus(
          detected: rightHandDetected,
          actualPoints: actualRightHandPoints,
          requiredPoints: 21,
        ),
        leftHand: LandmarkPartStatus(
          detected: leftHandDetected,
          actualPoints: actualLeftHandPoints,
          requiredPoints: 21,
        ),
        modelFaceLipPoints: actualModelFaceLipPoints,
        modelBodyHeadPoints: actualModelBodyHeadPoints,
        totalModelPoints: actualTotalModelPoints,
        fps: _currentFps,
      );
    } catch (e) {
      debugPrint('[VisionDetectionService] Error processing frame: $e');
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  void _calcFps() {
    _fpsFrameCounter++;
    final now = DateTime.now();
    if (_lastFpsCalcTime == null) {
      _lastFpsCalcTime = now;
      return;
    }
    final elapsed = now.difference(_lastFpsCalcTime!).inMilliseconds;
    if (elapsed >= 1000) {
      _currentFps = (_fpsFrameCounter * 1000.0) / elapsed;
      _fpsFrameCounter = 0;
      _lastFpsCalcTime = now;
    }
  }

  /// تحويل إطار الكاميرا إلى InputImage لـ ML Kit
  InputImage? _createInputImage(
    CameraImage image, {
    int? sensorOrientation,
    bool isFrontCamera = true,
    required DeviceOrientation deviceOrientation,
  }) {
    if (image.planes.isEmpty) return null;

    final inputRotation = _inputRotationFromCamera(
      sensorOrientation: sensorOrientation,
      isFrontCamera: isFrontCamera,
      deviceOrientation: deviceOrientation,
    );

    try {
      if (defaultTargetPlatform == TargetPlatform.android &&
          image.format.group == ImageFormatGroup.yuv420) {
        final int width = image.width;
        final int height = image.height;
        final int ySize = width * height;
        final int uvSize = width * height ~/ 2;
        final Uint8List nv21 = Uint8List(ySize + uvSize);

        final yPlane = image.planes[0];
        final yBytes = yPlane.bytes;
        final int yRowStride = yPlane.bytesPerRow;
        final int yPixelStride = yPlane.bytesPerPixel ?? 1;

        int dstIdx = 0;
        for (int y = 0; y < height; y++) {
          final int rowStart = y * yRowStride;
          for (int x = 0; x < width; x++) {
            nv21[dstIdx++] = yBytes[rowStart + x * yPixelStride];
          }
        }

        final uPlane = image.planes[1];
        final vPlane = image.planes[2];
        final uBytes = uPlane.bytes;
        final vBytes = vPlane.bytes;
        final int uRowStride = uPlane.bytesPerRow;
        final int vRowStride = vPlane.bytesPerRow;
        final int uPixelStride = uPlane.bytesPerPixel ?? 1;
        final int vPixelStride = vPlane.bytesPerPixel ?? 1;

        final int uvHeight = height ~/ 2;
        final int uvWidth = width ~/ 2;

        for (int y = 0; y < uvHeight; y++) {
          final int uRowStart = y * uRowStride;
          final int vRowStart = y * vRowStride;
          for (int x = 0; x < uvWidth; x++) {
            nv21[dstIdx++] = vBytes[vRowStart + x * vPixelStride];
            nv21[dstIdx++] = uBytes[uRowStart + x * uPixelStride];
          }
        }

        return InputImage.fromBytes(
          bytes: nv21,
          metadata: InputImageMetadata(
            size: Size(width.toDouble(), height.toDouble()),
            rotation: inputRotation,
            format: InputImageFormat.nv21,
            bytesPerRow: width,
          ),
        );
      } else {
        final WriteBuffer allBytes = WriteBuffer();
        for (final Plane plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        final bytes = allBytes.done().buffer.asUint8List();

        return InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: inputRotation,
            format: InputImageFormat.bgra8888,
            bytesPerRow: image.planes.first.bytesPerRow,
          ),
        );
      }
    } catch (e) {
      debugPrint('[VisionDetectionService] Image conversion error: $e');
      return null;
    }
  }

  InputImageRotation _inputRotationFromCamera({
    int? sensorOrientation,
    bool isFrontCamera = true,
    required DeviceOrientation deviceOrientation,
  }) {
    final sensor = sensorOrientation ?? 90;
    final deviceAngle = switch (deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };

    final rotationDegrees = isFrontCamera
        ? (sensor + deviceAngle) % 360
        : (sensor - deviceAngle + 360) % 360;

    return InputImageRotationValue.fromRawValue(rotationDegrees) ??
        InputImageRotation.rotation0deg;
  }

  void reset() {
    _personStabilizer.reset();
    _headStabilizer.reset();
    _faceStabilizer.reset();
    _lipsStabilizer.reset();
    _leftHandStabilizer.reset();
    _rightHandStabilizer.reset();
  }

  Future<void> dispose() async {
    await _poseDetector?.close();
    await _faceMeshDetector?.close();
    await _handDetector?.dispose();
    _poseDetector = null;
    _faceMeshDetector = null;
    _handDetector = null;
    _isInitialized = false;
  }
}
