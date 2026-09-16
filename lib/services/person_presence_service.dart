import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:ishara/services/diagnostics/diagnostic_models.dart';

/// نتيجة كشف حضور الشخص والوضعية من إطار الكاميرا
class PersonPresenceResult {
  final bool personPresent;
  final bool posePresent;
  final bool headPresent;
  final bool facePresent;
  final bool lipsPresent;
  final int poseCount;
  final int landmarkCount;
  final int faceLandmarksCount;
  final bool noseValid;
  final bool leftShoulderValid;
  final bool rightShoulderValid;
  final bool leftHipValid;
  final bool rightHipValid;
  final double bestConfidence;
  final int previewRotation;
  final int detectorInputRotation;
  final bool imageConversionOk;
  final String? imageConversionError;
  final List<List<double>>? bodyPoints; // 25 نقطة Upper Body MediaPipe
  final List<List<double>>? lipPoints; // 19 نقطة Lip Contour

  const PersonPresenceResult({
    required this.personPresent,
    required this.posePresent,
    required this.headPresent,
    required this.facePresent,
    required this.lipsPresent,
    required this.poseCount,
    required this.landmarkCount,
    required this.faceLandmarksCount,
    required this.noseValid,
    required this.leftShoulderValid,
    required this.rightShoulderValid,
    required this.leftHipValid,
    required this.rightHipValid,
    required this.bestConfidence,
    this.previewRotation = 0,
    this.detectorInputRotation = 0,
    this.imageConversionOk = true,
    this.imageConversionError,
    this.bodyPoints,
    this.lipPoints,
  });

  static const PersonPresenceResult empty = PersonPresenceResult(
    personPresent: false,
    posePresent: false,
    headPresent: false,
    facePresent: false,
    lipsPresent: false,
    poseCount: 0,
    landmarkCount: 0,
    faceLandmarksCount: 0,
    noseValid: false,
    leftShoulderValid: false,
    rightShoulderValid: false,
    leftHipValid: false,
    rightHipValid: false,
    bestConfidence: 0.0,
    previewRotation: 0,
    detectorInputRotation: 0,
    imageConversionOk: false,
  );
}

/// خدمة كشف حضور الشخص والوضعية الموثوقة عبر Google ML Kit Pose Detection (STREAM_MODE)
class PersonPresenceService {
  PoseDetector? _detector;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// تهيئة محرك Pose Detection بوضع البث المباشر المستمر (Stream Mode)
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _detector = PoseDetector(
        options: PoseDetectorOptions(
          model: PoseDetectionModel.base,
          mode: PoseDetectionMode.stream,
        ),
      );
      _isInitialized = true;
      debugPrint('[PersonPresenceService] ✅ PoseDetector initialized successfully (Stream Mode)');
    } catch (e, stack) {
      _detector = null;
      _isInitialized = false;
      debugPrint('[PersonPresenceService] ❌ Failed to initialize PoseDetector: $e\n$stack');
    }
  }

  /// كشف الشخص والوضعية من إطار CameraImage
  Future<PersonPresenceResult> detectFromCameraImage(
    CameraImage image, {
    int? sensorOrientation,
    bool isFrontCamera = false,
    DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp,
  }) async {
    if (!_isInitialized || _detector == null) {
      debugPrint('[PersonPresenceService] ${DiagnosticErrorCodes.e101PersonDetectorNotCalled}: detector not initialized');
      return PersonPresenceResult.empty;
    }

    // ──────────────── B7: حساب وطباعة زوايا الدوران بدقة ────────────────
    final int previewRotation = sensorOrientation ?? 90;
    final int deviceAngle = switch (deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };

    final int detectorInputRotation = isFrontCamera
        ? (previewRotation + deviceAngle) % 360
        : (previewRotation - deviceAngle + 360) % 360;

    debugPrint('PREVIEW ROTATION: $previewRotation°');
    debugPrint('DETECTOR INPUT ROTATION: $detectorInputRotation°');

    // ──────────────── B6: فحص وتحويل صورة YUV420 إلى NV21 ────────────────
    debugPrint(
      'CAMERA IMAGE: ${image.width}x${image.height} | format: ${image.format.group.name} | '
      'planes: ${image.planes.length} | Y rowStride: ${image.planes.isNotEmpty ? image.planes[0].bytesPerRow : 0} | '
      'sensor: $sensorOrientation | front: $isFrontCamera | device: $deviceOrientation',
    );

    final inputImage = _createInputImage(
      image,
      sensorOrientation: sensorOrientation,
      isFrontCamera: isFrontCamera,
      deviceOrientation: deviceOrientation,
    );

    if (inputImage == null) {
      debugPrint('ERROR: ${DiagnosticErrorCodes.e110ImageConversionFailed}');
      return PersonPresenceResult(
        personPresent: false,
        posePresent: false,
        headPresent: false,
        facePresent: false,
        lipsPresent: false,
        poseCount: 0,
        landmarkCount: 0,
        faceLandmarksCount: 0,
        noseValid: false,
        leftShoulderValid: false,
        rightShoulderValid: false,
        leftHipValid: false,
        rightHipValid: false,
        bestConfidence: 0.0,
        previewRotation: previewRotation,
        detectorInputRotation: detectorInputRotation,
        imageConversionOk: false,
        imageConversionError: DiagnosticErrorCodes.e110ImageConversionFailed,
      );
    }

    try {
      final List<Pose> poses = await _detector!.processImage(inputImage);

      if (poses.isEmpty) {
        debugPrint('POSE LANDMARKS = 0');
        debugPrint('FACE LANDMARKS = 0');
        return PersonPresenceResult(
          personPresent: false,
          posePresent: false,
          headPresent: false,
          facePresent: false,
          lipsPresent: false,
          poseCount: 0,
          landmarkCount: 0,
          faceLandmarksCount: 0,
          noseValid: false,
          leftShoulderValid: false,
          rightShoulderValid: false,
          leftHipValid: false,
          rightHipValid: false,
          bestConfidence: 0.0,
          previewRotation: previewRotation,
          detectorInputRotation: detectorInputRotation,
          imageConversionOk: true,
        );
      }

      final pose = poses.first;
      final landmarks = pose.landmarks;

      // فحص معالم الرأس والوجه
      final nose = landmarks[PoseLandmarkType.nose];
      final leftEyeInner = landmarks[PoseLandmarkType.leftEyeInner];
      final leftEye = landmarks[PoseLandmarkType.leftEye];
      final leftEyeOuter = landmarks[PoseLandmarkType.leftEyeOuter];
      final rightEyeInner = landmarks[PoseLandmarkType.rightEyeInner];
      final rightEye = landmarks[PoseLandmarkType.rightEye];
      final rightEyeOuter = landmarks[PoseLandmarkType.rightEyeOuter];
      final leftEar = landmarks[PoseLandmarkType.leftEar];
      final rightEar = landmarks[PoseLandmarkType.rightEar];
      final leftMouth = landmarks[PoseLandmarkType.leftMouth];
      final rightMouth = landmarks[PoseLandmarkType.rightMouth];

      final noseValid = _isValid(nose);
      final leftEyeValid = _isValid(leftEye) || _isValid(leftEyeInner) || _isValid(leftEyeOuter);
      final rightEyeValid = _isValid(rightEye) || _isValid(rightEyeInner) || _isValid(rightEyeOuter);
      final leftEarValid = _isValid(leftEar);
      final rightEarValid = _isValid(rightEar);
      final mouthValid = _isValid(leftMouth) || _isValid(rightMouth);

      int faceLandmarksCount = 0;
      for (final lm in [
        nose, leftEyeInner, leftEye, leftEyeOuter,
        rightEyeInner, rightEye, rightEyeOuter,
        leftEar, rightEar, leftMouth, rightMouth,
      ]) {
        if (_isValid(lm)) faceLandmarksCount++;
      }

      // فحص الجذع العلوي
      final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
      final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
      final leftHip = landmarks[PoseLandmarkType.leftHip];
      final rightHip = landmarks[PoseLandmarkType.rightHip];

      final leftShoulderValid = _isValid(leftShoulder);
      final rightShoulderValid = _isValid(rightShoulder);
      final leftHipValid = _isValid(leftHip);
      final rightHipValid = _isValid(rightHip);

      // حساب أفضل درجة ثقة
      double bestConfidence = 0.0;
      for (final lm in landmarks.values) {
        if (lm.likelihood > bestConfidence) {
          bestConfidence = lm.likelihood;
        }
      }

      // ──────────────── B4: الوجود يعتمد على Pose OR Head OR Face ────────────────
      final bool posePresent = landmarks.isNotEmpty &&
          (leftShoulderValid || rightShoulderValid || leftHipValid || rightHipValid);
      final bool facePresent = faceLandmarksCount >= 2 || noseValid || leftEyeValid || rightEyeValid;
      final bool headPresent = (noseValid && (leftEarValid || rightEarValid || faceLandmarksCount >= 2)) ||
          (leftEyeValid && rightEyeValid);

      final bool personPresent = posePresent || headPresent || facePresent;

      // ──────────────── B8: طباعة عدد المعالم بدقة ────────────────
      debugPrint('POSE LANDMARKS = ${landmarks.length}');
      debugPrint('FACE LANDMARKS = $faceLandmarksCount');
      if (personPresent) {
        debugPrint('PERSON = true');
      }

      // ──────────────── استخراج معالم الجسم العلوي الـ 25 بنسب [0..1] ────────────────
      final bodyPoints = _extractUpperBody25(
        landmarks: landmarks,
        imageWidth: image.width,
        imageHeight: image.height,
        rotation: detectorInputRotation,
      );

      // استخراج معالم الشفاه الـ 19
      final lipPoints = _extractLips19(
        leftMouth: leftMouth,
        rightMouth: rightMouth,
        nose: nose,
        imageWidth: image.width,
        imageHeight: image.height,
        rotation: detectorInputRotation,
      );

      return PersonPresenceResult(
        personPresent: personPresent,
        posePresent: posePresent,
        headPresent: headPresent,
        facePresent: facePresent,
        lipsPresent: mouthValid,
        poseCount: poses.length,
        landmarkCount: landmarks.length,
        faceLandmarksCount: faceLandmarksCount,
        noseValid: noseValid,
        leftShoulderValid: leftShoulderValid,
        rightShoulderValid: rightShoulderValid,
        leftHipValid: leftHipValid,
        rightHipValid: rightHipValid,
        bestConfidence: bestConfidence,
        previewRotation: previewRotation,
        detectorInputRotation: detectorInputRotation,
        imageConversionOk: true,
        bodyPoints: bodyPoints,
        lipPoints: lipPoints,
      );
    } catch (e, stack) {
      debugPrint('ERROR: ${DiagnosticErrorCodes.e102PersonDetectorException}');
      debugPrint('Exception type: ${e.runtimeType}');
      debugPrint('Exception message: $e');
      debugPrint('StackTrace:\n$stack');

      return PersonPresenceResult(
        personPresent: false,
        posePresent: false,
        headPresent: false,
        facePresent: false,
        lipsPresent: false,
        poseCount: 0,
        landmarkCount: 0,
        faceLandmarksCount: 0,
        noseValid: false,
        leftShoulderValid: false,
        rightShoulderValid: false,
        leftHipValid: false,
        rightHipValid: false,
        bestConfidence: 0.0,
        previewRotation: previewRotation,
        detectorInputRotation: detectorInputRotation,
        imageConversionOk: true,
        imageConversionError: e.toString(),
      );
    }
  }

  /// تحويل إطار الكاميرا إلى InputImage مع بناء NV21 بدقة على Android
  InputImage? _createInputImage(
    CameraImage image, {
    int? sensorOrientation,
    bool isFrontCamera = false,
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

        // 1. نسخ مستوي Y سطراً بسطر لمراعاة bytesPerRow
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

        // 2. تجميع مستوي VU لـ NV21
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
        // للمنصات الأخرى أو تنسيق BGRA8888
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
      debugPrint('[PersonPresenceService] ❌ ${DiagnosticErrorCodes.e110ImageConversionFailed}: $e');
      return null;
    }
  }

  InputImageRotation _inputRotationFromCamera({
    int? sensorOrientation,
    bool isFrontCamera = false,
    required DeviceOrientation deviceOrientation,
  }) {
    final sensor = sensorOrientation ?? 90;
    final deviceAngle = switch (deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };

    final int totalRotation = isFrontCamera
        ? (sensor + deviceAngle) % 360
        : (sensor - deviceAngle + 360) % 360;

    return switch (totalRotation) {
      0 => InputImageRotation.rotation0deg,
      90 => InputImageRotation.rotation90deg,
      180 => InputImageRotation.rotation180deg,
      _ => InputImageRotation.rotation270deg,
    };
  }

  /// استخراج معالم Upper Body الـ 25 بنسب [0..1]
  List<List<double>> _extractUpperBody25({
    required Map<PoseLandmarkType, PoseLandmark> landmarks,
    required int imageWidth,
    required int imageHeight,
    required int rotation,
  }) {
    final bodyPoints = List.generate(25, (_) => [0.0, 0.0]);
    final types = [
      PoseLandmarkType.nose, // 0
      PoseLandmarkType.leftEyeInner, // 1
      PoseLandmarkType.leftEye, // 2
      PoseLandmarkType.leftEyeOuter, // 3
      PoseLandmarkType.rightEyeInner, // 4
      PoseLandmarkType.rightEye, // 5
      PoseLandmarkType.rightEyeOuter, // 6
      PoseLandmarkType.leftEar, // 7
      PoseLandmarkType.rightEar, // 8
      PoseLandmarkType.leftMouth, // 9
      PoseLandmarkType.rightMouth, // 10
      PoseLandmarkType.leftShoulder, // 11
      PoseLandmarkType.rightShoulder, // 12
      PoseLandmarkType.leftElbow, // 13
      PoseLandmarkType.rightElbow, // 14
      PoseLandmarkType.leftWrist, // 15
      PoseLandmarkType.rightWrist, // 16
      PoseLandmarkType.leftPinky, // 17
      PoseLandmarkType.rightPinky, // 18
      PoseLandmarkType.leftIndex, // 19
      PoseLandmarkType.rightIndex, // 20
      PoseLandmarkType.leftThumb, // 21
      PoseLandmarkType.rightThumb, // 22
      PoseLandmarkType.leftHip, // 23
      PoseLandmarkType.rightHip, // 24
    ];

    final double effectiveWidth = (rotation == 90 || rotation == 270)
        ? imageHeight.toDouble()
        : imageWidth.toDouble();
    final double effectiveHeight = (rotation == 90 || rotation == 270)
        ? imageWidth.toDouble()
        : imageHeight.toDouble();

    for (int i = 0; i < types.length; i++) {
      final lm = landmarks[types[i]];
      if (lm != null && _isValid(lm) && effectiveWidth > 0 && effectiveHeight > 0) {
        bodyPoints[i] = [
          (lm.x / effectiveWidth).clamp(0.0, 1.0),
          (lm.y / effectiveHeight).clamp(0.0, 1.0),
        ];
      }
    }

    return bodyPoints;
  }

  /// استخراج معالم الشفاه الـ 19 من زوايا الفم
  List<List<double>> _extractLips19({
    required PoseLandmark? leftMouth,
    required PoseLandmark? rightMouth,
    required PoseLandmark? nose,
    required int imageWidth,
    required int imageHeight,
    required int rotation,
  }) {
    final lipPoints = List.generate(19, (_) => [0.0, 0.0]);
    final double effectiveWidth = (rotation == 90 || rotation == 270)
        ? imageHeight.toDouble()
        : imageWidth.toDouble();
    final double effectiveHeight = (rotation == 90 || rotation == 270)
        ? imageWidth.toDouble()
        : imageHeight.toDouble();

    if (effectiveWidth <= 0 || effectiveHeight <= 0) return lipPoints;

    double centerX = 0.5;
    double centerY = 0.35;
    double radiusX = 0.04;
    double radiusY = 0.02;

    if (leftMouth != null && rightMouth != null && _isValid(leftMouth) && _isValid(rightMouth)) {
      final mx1 = leftMouth.x / effectiveWidth;
      final my1 = leftMouth.y / effectiveHeight;
      final mx2 = rightMouth.x / effectiveWidth;
      final my2 = rightMouth.y / effectiveHeight;
      centerX = (mx1 + mx2) / 2.0;
      centerY = (my1 + my2) / 2.0;
      radiusX = (mx1 - mx2).abs() / 2.0;
      if (radiusX < 0.02) radiusX = 0.02;
      radiusY = radiusX * 0.5;
    } else if (nose != null && _isValid(nose)) {
      centerX = (nose.x / effectiveWidth).clamp(0.2, 0.8);
      centerY = ((nose.y / effectiveHeight) + 0.05).clamp(0.2, 0.8);
    }

    for (int i = 0; i < 19; i++) {
      final double angle = (i / 19.0) * 2 * pi;
      lipPoints[i] = [
        (centerX + cos(angle) * radiusX).clamp(0.0, 1.0),
        (centerY + sin(angle) * radiusY).clamp(0.0, 1.0),
      ];
    }

    return lipPoints;
  }

  static bool _isValid(PoseLandmark? landmark) {
    if (landmark == null) return false;
    final absX = landmark.x.abs();
    final absY = landmark.y.abs();
    return absX > 1e-6 && absY > 1e-6 && landmark.likelihood >= 0.25;
  }

  Future<void> dispose() async {
    try {
      await _detector?.close();
    } catch (_) {}
    _detector = null;
    _isInitialized = false;
  }
}
