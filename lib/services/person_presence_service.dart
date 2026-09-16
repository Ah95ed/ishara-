import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PersonPresenceResult {
  final bool personPresent;
  final bool posePresent;
  final int poseCount;
  final int landmarkCount;
  final bool noseValid;
  final bool leftShoulderValid;
  final bool rightShoulderValid;
  final bool leftHipValid;
  final bool rightHipValid;
  final double bestConfidence;

  const PersonPresenceResult({
    required this.personPresent,
    required this.posePresent,
    required this.poseCount,
    required this.landmarkCount,
    required this.noseValid,
    required this.leftShoulderValid,
    required this.rightShoulderValid,
    required this.leftHipValid,
    required this.rightHipValid,
    required this.bestConfidence,
  });

  static const PersonPresenceResult empty = PersonPresenceResult(
    personPresent: false,
    posePresent: false,
    poseCount: 0,
    landmarkCount: 0,
    noseValid: false,
    leftShoulderValid: false,
    rightShoulderValid: false,
    leftHipValid: false,
    rightHipValid: false,
    bestConfidence: 0.0,
  );
}

class PersonPresenceService {
  PoseDetector? _detector;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

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
    } catch (e) {
      _detector = null;
      _isInitialized = false;
      if (kDebugMode) {
        debugPrint(
          '[PersonPresenceService] ⚠️ Failed to initialize PoseDetector: $e',
        );
      }
    }
  }

  Future<PersonPresenceResult> detectFromCameraImage(
    CameraImage image, {
    int? sensorOrientation,
    bool isFrontCamera = false,
    DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp,
  }) async {
    if (!_isInitialized || _detector == null) {
      debugPrint(
        '[PersonPresenceService] E102_PERSON_DETECTOR_NOT_CALLED: detector not initialized',
      );
      return PersonPresenceResult.empty;
    }

    try {
      debugPrint(
        '[PersonPresenceService] CAMERA FORMAT: ${image.format.group.name} | SIZE: ${image.width}x${image.height} | SENSOR ORIENTATION: ${sensorOrientation ?? 'null'} | DEVICE ORIENTATION: $deviceOrientation',
      );

      final inputImage = _createInputImage(
        image,
        sensorOrientation: sensorOrientation,
        deviceOrientation: deviceOrientation,
      );
      if (inputImage == null) {
        debugPrint(
          '[PersonPresenceService] E104_CAMERA_IMAGE_CONVERSION: image conversion failed',
        );
        return PersonPresenceResult.empty;
      }

      final poses = await _detector!.processImage(inputImage);
      if (poses.isEmpty) {
        if (kDebugMode) {
          debugPrint('[PersonPresenceService] POSE COUNT: 0');
        }
        return PersonPresenceResult.empty;
      }

      final pose = poses.first;
      final landmarks = pose.landmarks;
      final noseValid = _isValid(landmarks[PoseLandmarkType.nose]);
      final leftShoulderValid = _isValid(
        landmarks[PoseLandmarkType.leftShoulder],
      );
      final rightShoulderValid = _isValid(
        landmarks[PoseLandmarkType.rightShoulder],
      );
      final leftHipValid = _isValid(landmarks[PoseLandmarkType.leftHip]);
      final rightHipValid = _isValid(landmarks[PoseLandmarkType.rightHip]);
      final validCount = [
        noseValid,
        leftShoulderValid,
        rightShoulderValid,
        leftHipValid,
        rightHipValid,
      ].where((v) => v).length;
      final bestConfidence = [
        landmarks[PoseLandmarkType.nose]?.likelihood,
        landmarks[PoseLandmarkType.leftShoulder]?.likelihood,
        landmarks[PoseLandmarkType.rightShoulder]?.likelihood,
        landmarks[PoseLandmarkType.leftHip]?.likelihood,
        landmarks[PoseLandmarkType.rightHip]?.likelihood,
      ].whereType<double>().fold<double>(0.0, (a, b) => a > b ? a : b);

      final bool personPresent =
          landmarks.isNotEmpty &&
          (validCount >= 2 ||
              (noseValid && (leftShoulderValid || rightShoulderValid)));

      if (kDebugMode) {
        debugPrint('[PersonPresenceService] POSE COUNT: ${poses.length}');
        debugPrint('[PersonPresenceService] LANDMARKS: ${landmarks.length}');
        debugPrint(
          '[PersonPresenceService] NOSE: ${noseValid ? 'valid' : 'invalid'} confidence=${landmarks[PoseLandmarkType.nose]?.likelihood ?? 0.0}',
        );
        debugPrint(
          '[PersonPresenceService] LEFT_SHOULDER: ${leftShoulderValid ? 'valid' : 'invalid'} confidence=${landmarks[PoseLandmarkType.leftShoulder]?.likelihood ?? 0.0}',
        );
        debugPrint(
          '[PersonPresenceService] RIGHT_SHOULDER: ${rightShoulderValid ? 'valid' : 'invalid'} confidence=${landmarks[PoseLandmarkType.rightShoulder]?.likelihood ?? 0.0}',
        );
        debugPrint(
          '[PersonPresenceService] LEFT_HIP: ${leftHipValid ? 'valid' : 'invalid'} confidence=${landmarks[PoseLandmarkType.leftHip]?.likelihood ?? 0.0}',
        );
        debugPrint(
          '[PersonPresenceService] RIGHT_HIP: ${rightHipValid ? 'valid' : 'invalid'} confidence=${landmarks[PoseLandmarkType.rightHip]?.likelihood ?? 0.0}',
        );
      }

      return PersonPresenceResult(
        personPresent: personPresent,
        posePresent: poses.isNotEmpty,
        poseCount: poses.length,
        landmarkCount: landmarks.length,
        noseValid: noseValid,
        leftShoulderValid: leftShoulderValid,
        rightShoulderValid: rightShoulderValid,
        leftHipValid: leftHipValid,
        rightHipValid: rightHipValid,
        bestConfidence: bestConfidence,
      );
    } catch (e, stackTrace) {
      debugPrint('[PersonPresenceService] pose detection error: $e');
      debugPrint(stackTrace.toString());
      return PersonPresenceResult.empty;
    }
  }

  InputImage? _createInputImage(
    CameraImage image, {
    int? sensorOrientation,
    required DeviceOrientation deviceOrientation,
  }) {
    if (image.planes.isEmpty) return null;

    final imageFormat = _inputImageFormatFromCamera(image);
    final inputRotation = _inputRotationFromCamera(
      sensorOrientation: sensorOrientation,
      deviceOrientation: deviceOrientation,
    );

    // Concatenate all planes into a single byte array for YUV420 so that
    // native ML Kit doesn't crash on incomplete buffer length
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
        format: imageFormat,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  InputImageFormat _inputImageFormatFromCamera(CameraImage image) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (image.format.group == ImageFormatGroup.yuv420) {
        return InputImageFormat.yuv_420_888;
      }
      return InputImageFormat.nv21;
    }

    return InputImageFormat.bgra8888;
  }

  InputImageRotation _inputRotationFromCamera({
    int? sensorOrientation,
    required DeviceOrientation deviceOrientation,
  }) {
    final sensor = sensorOrientation ?? 90;
    final deviceAngle = switch (deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };

    final int totalRotation = (sensor - deviceAngle + 360) % 360;
    return switch (totalRotation) {
      0 => InputImageRotation.rotation0deg,
      90 => InputImageRotation.rotation90deg,
      180 => InputImageRotation.rotation180deg,
      _ => InputImageRotation.rotation270deg,
    };
  }

  static bool _isValid(PoseLandmark? landmark) {
    if (landmark == null) return false;
    final absX = landmark.x.abs();
    final absY = landmark.y.abs();
    return absX > 1e-6 && absY > 1e-6 && landmark.likelihood >= 0.3;
  }

  Future<void> dispose() async {
    try {
      await _detector?.close();
    } catch (_) {}
    _detector = null;
    _isInitialized = false;
  }
}
