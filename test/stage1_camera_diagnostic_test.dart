import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/services/diagnostics/diagnostic_models.dart';
import 'package:ishara/services/diagnostics/ishara_diagnostic_service.dart';

void main() {
  group('Stage 1: Camera Diagnostic & Telemetry Tests', () {
    late IsharaDiagnosticService diagService;

    setUp(() {
      diagService = IsharaDiagnosticService();
    });

    test('Stage 1: Healthy camera streaming records PASS status', () {
      diagService.recordCamera(
        isInitialized: true,
        isStreaming: true,
        fps: 15.2,
        frameAgeMs: 66,
        width: 640,
        height: 480,
        format: 'yuv420',
        rotation: 270,
        previewRotation: 270,
        detectorInputRotation: 270,
        isFrontCamera: true,
        framesReceived: 100,
      );

      final camera = diagService.camera;
      expect(camera.status, equals(DiagnosticStageStatus.pass));
      expect(camera.fps, closeTo(15.2, 0.01));
      expect(camera.width, equals(640));
      expect(camera.height, equals(480));
      expect(camera.format, equals('yuv420'));
      expect(camera.previewRotation, equals(270));
      expect(camera.detectorInputRotation, equals(270));
      expect(camera.isFrontCamera, isTrue);
      expect(camera.errorCode, isNull);
    });

    test('Stage 1: Uninitialized camera reports E100_CAMERA', () {
      diagService.recordCamera(
        isInitialized: false,
        isStreaming: false,
        fps: 0.0,
        frameAgeMs: 0,
        width: 0,
        height: 0,
        format: 'unknown',
        rotation: 0,
        previewRotation: 0,
        detectorInputRotation: 0,
        isFrontCamera: true,
      );

      final camera = diagService.camera;
      expect(camera.status, equals(DiagnosticStageStatus.fail));
      expect(camera.errorCode, equals(DiagnosticErrorCodes.e100Camera));
    });

    test('Stage 1: Halted stream (frameAge >= 1500ms) reports E101_CAMERA_FRAME', () {
      diagService.recordCamera(
        isInitialized: true,
        isStreaming: false,
        fps: 0.0,
        frameAgeMs: 2500,
        width: 640,
        height: 480,
        format: 'yuv420',
        rotation: 270,
        previewRotation: 270,
        detectorInputRotation: 270,
        isFrontCamera: true,
      );

      final camera = diagService.camera;
      expect(camera.status, equals(DiagnosticStageStatus.fail));
      expect(camera.errorCode, equals(DiagnosticErrorCodes.e101CameraFrame));
    });

    test('Stage 1: Empty or unknown format reports E102_IMAGE_FORMAT', () {
      diagService.recordCamera(
        isInitialized: true,
        isStreaming: true,
        fps: 15.0,
        frameAgeMs: 50,
        width: 640,
        height: 480,
        format: 'UNKNOWN',
        rotation: 270,
        previewRotation: 270,
        detectorInputRotation: 270,
        isFrontCamera: true,
      );

      final camera = diagService.camera;
      expect(camera.status, equals(DiagnosticStageStatus.fail));
      expect(camera.errorCode, equals(DiagnosticErrorCodes.e102ImageFormat));
    });

    test('Stage 1: Invalid rotation angle reports E103_ROTATION', () {
      diagService.recordCamera(
        isInitialized: true,
        isStreaming: true,
        fps: 15.0,
        frameAgeMs: 50,
        width: 640,
        height: 480,
        format: 'yuv420',
        rotation: 45, // invalid angle
        previewRotation: 45,
        detectorInputRotation: 45,
        isFrontCamera: true,
      );

      final camera = diagService.camera;
      expect(camera.status, equals(DiagnosticStageStatus.fail));
      expect(camera.errorCode, equals(DiagnosticErrorCodes.e103Rotation));
    });
  });
}
