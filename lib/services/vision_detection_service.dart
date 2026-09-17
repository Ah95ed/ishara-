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
/// يمنع التذبذب السريع (Flickering) بدون أي تأخير زمني مصطنع.
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
/// الخدمة الموحدة الوحيدة المسؤولة عن معالجة إطارات الكاميرا
/// واستخراج الحالات الـ 6 (الشخص، الرأس، الوجه، الشفاه، اليد اليسرى، اليد اليمنى) في الوقت الحقيقي.
class VisionDetectionService {
  PoseDetector? _poseDetector;
  FaceMeshDetector? _faceMeshDetector;
  hd.HandDetector? _handDetector;

  bool _isInitialized = false;
  bool _isProcessing = false;

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
      // 1. كاشف الجسم والرأس (Google ML Kit Pose Detection - Stream Mode)
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

  /// معالجة إطار الكاميرا
  Future<BodyPartsDetectionState?> processFrame(
    CameraImage image, {
    int? sensorOrientation,
    bool isFrontCamera = true,
    DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp,
  }) async {
    if (!_isInitialized || _isProcessing) return null;

    // خفض الفريمات لمنع استهلاك المعالج وتراكم الطوابير (15-18 FPS)
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

      // ── 1 & 2: فحص وضعية الجسم والرأس ──
      bool rawPose = false;
      bool rawHead = false;
      int poseLandmarksCount = 0;

      if (poses.isNotEmpty) {
        final pose = poses.first;
        final landmarks = pose.landmarks;
        poseLandmarksCount = landmarks.length;

        // فحص الكتفين والحوض
        final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
        final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
        final leftHip = landmarks[PoseLandmarkType.leftHip];
        final rightHip = landmarks[PoseLandmarkType.rightHip];

        final bool hasTorso = (leftShoulder != null && leftShoulder.likelihood > 0.35) ||
            (rightShoulder != null && rightShoulder.likelihood > 0.35) ||
            (leftHip != null && leftHip.likelihood > 0.35) ||
            (rightHip != null && rightHip.likelihood > 0.35);

        rawPose = landmarks.isNotEmpty && hasTorso;

        // فحص معالم الرأس
        final nose = landmarks[PoseLandmarkType.nose];
        final leftEye = landmarks[PoseLandmarkType.leftEye];
        final rightEye = landmarks[PoseLandmarkType.rightEye];
        final leftEar = landmarks[PoseLandmarkType.leftEar];
        final rightEar = landmarks[PoseLandmarkType.rightEar];

        int headPoints = 0;
        for (final p in [nose, leftEye, rightEye, leftEar, rightEar]) {
          if (p != null && p.likelihood > 0.35) {
            headPoints++;
          }
        }
        rawHead = headPoints >= 2;
      }

      // ── 3 & 4: فحص الوجه والشفاه عبر Face Mesh ──
      bool rawFace = false;
      bool rawLips = false;
      int faceLandmarksCount = 0;

      if (faceMeshes.isNotEmpty) {
        final mesh = faceMeshes.first;
        faceLandmarksCount = mesh.points.length;
        rawFace = faceLandmarksCount >= 30;

        // عند ثبوت وجود شبكة الوجه، يُعتبر الرأس محققاً أيضاً
        if (rawFace) {
          rawHead = true;
        }

        // فحص حدود الشفتين
        final upperTop = mesh.contours[FaceMeshContourType.upperLipTop];
        final upperBottom = mesh.contours[FaceMeshContourType.upperLipBottom];
        final lowerTop = mesh.contours[FaceMeshContourType.lowerLipTop];
        final lowerBottom = mesh.contours[FaceMeshContourType.lowerLipBottom];

        final int lipPointsCount = (upperTop?.length ?? 0) +
            (upperBottom?.length ?? 0) +
            (lowerTop?.length ?? 0) +
            (lowerBottom?.length ?? 0);

        rawLips = lipPointsCount >= 8;
      }

      // ── 1: الشخص = وجود وضعية جسم OR رأس OR وجه (الجهة لا تشترط اليد أبداً!) ──
      final bool rawPerson = rawPose || rawHead || rawFace;

      // ── 5 & 6: فحص اليد اليسرى واليد اليمنى ──
      bool rawLeftHand = false;
      bool rawRightHand = false;
      int leftHandPoints = 0;
      int rightHandPoints = 0;

      for (final hand in hands) {
        if (hand.hasLandmarks && hand.landmarks.length == 21) {
          if (hand.handedness == hd.Handedness.left) {
            rawLeftHand = true;
            leftHandPoints = 21;
          } else if (hand.handedness == hd.Handedness.right) {
            rawRightHand = true;
            rightHandPoints = 21;
          }
        }
      }

      // ── تطبيق الموازنة Frame-based Stabilization ──
      final bool person = _personStabilizer.update(rawPerson);
      final bool head = _headStabilizer.update(rawHead);
      final bool face = _faceStabilizer.update(rawFace);
      final bool lips = _lipsStabilizer.update(rawLips);
      final bool leftHand = _leftHandStabilizer.update(rawLeftHand);
      final bool rightHand = _rightHandStabilizer.update(rawRightHand);

      // ── طباعة Console المطلوبة بحذافيرها ──
      debugPrint('========================================');
      debugPrint('PERSON: $person');
      debugPrint('HEAD: $head');
      debugPrint('FACE: $face');
      debugPrint('LIPS: $lips');
      debugPrint('LEFT HAND: ${leftHand ? 21 : 0}');
      debugPrint('RIGHT HAND: ${rightHand ? 21 : 0}');
      debugPrint('FPS: ${_currentFps.toStringAsFixed(1)}');
      debugPrint('========================================');

      return BodyPartsDetectionState(
        person: person,
        head: head,
        face: face,
        lips: lips,
        leftHand: leftHand,
        rightHand: rightHand,
        leftHandLandmarks: leftHand ? leftHandPoints : 0,
        rightHandLandmarks: rightHand ? rightHandPoints : 0,
        faceLandmarksCount: faceLandmarksCount,
        poseLandmarksCount: poseLandmarksCount,
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
