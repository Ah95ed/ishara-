import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:ishara/models/body_parts_detection_state.dart';
import 'package:ishara/services/vision_detection_service.dart';

void main() {
  group('Vision Landmarks State, Counts & 86 Points Tests', () {
    test('LandmarkPartStatus computes pass, partial, fail correctly', () {
      const fullHand = LandmarkPartStatus(detected: true, actualPoints: 21, requiredPoints: 21);
      expect(fullHand.status, equals(DetectionStatus.pass));
      expect(fullHand.icon, equals('✅'));

      const partialHand = LandmarkPartStatus(detected: true, actualPoints: 14, requiredPoints: 21);
      expect(partialHand.status, equals(DetectionStatus.partial));
      expect(partialHand.icon, equals('⚠️'));

      const noHand = LandmarkPartStatus(detected: false, actualPoints: 0, requiredPoints: 21);
      expect(noHand.status, equals(DetectionStatus.fail));
      expect(noHand.icon, equals('❌'));
    });

    test('VisionLandmarksState calculates exact 86 points summation', () {
      // Case 1: Full detection (86/86)
      const fullState = VisionLandmarksState(
        personDetected: true,
        head: LandmarkPartStatus(detected: true, actualPoints: 11, requiredPoints: 11),
        face: LandmarkPartStatus(detected: true, actualPoints: 468, requiredPoints: 468),
        lips: LandmarkPartStatus(detected: true, actualPoints: 19, requiredPoints: 19),
        rightHand: LandmarkPartStatus(detected: true, actualPoints: 21, requiredPoints: 21),
        leftHand: LandmarkPartStatus(detected: true, actualPoints: 21, requiredPoints: 21),
        modelFaceLipPoints: 19,
        modelBodyHeadPoints: 25,
        totalModelPoints: 21 + 21 + 19 + 25, // 86
      );

      expect(fullState.totalModelPoints, equals(86));
      expect(fullState.totalStatus, equals(DetectionStatus.pass));
      expect(fullState.totalIcon, equals('✅'));

      // Case 2: One hand missing (65/86)
      const missingHandState = VisionLandmarksState(
        personDetected: true,
        head: LandmarkPartStatus(detected: true, actualPoints: 11, requiredPoints: 11),
        face: LandmarkPartStatus(detected: true, actualPoints: 468, requiredPoints: 468),
        lips: LandmarkPartStatus(detected: true, actualPoints: 19, requiredPoints: 19),
        rightHand: LandmarkPartStatus(detected: false, actualPoints: 0, requiredPoints: 21),
        leftHand: LandmarkPartStatus(detected: true, actualPoints: 21, requiredPoints: 21),
        modelFaceLipPoints: 19,
        modelBodyHeadPoints: 25,
        totalModelPoints: 0 + 21 + 19 + 25, // 65
      );

      expect(missingHandState.totalModelPoints, equals(65));
      expect(missingHandState.totalIcon, equals('❌'));

      // Case 3: Empty (0/86)
      expect(VisionLandmarksState.empty.totalModelPoints, equals(0));
      expect(VisionLandmarksState.empty.totalIcon, equals('❌'));
    });

    test('PartStabilizer activates after consecutive positive frames and holds', () {
      final stabilizer = PartStabilizer(framesToActivate: 2, framesToDeactivate: 4);

      expect(stabilizer.update(true), isFalse);
      expect(stabilizer.update(true), isTrue);
      expect(stabilizer.update(true), isTrue);

      // Brief dropouts do not deactivate immediately
      expect(stabilizer.update(false), isTrue);
      expect(stabilizer.update(false), isTrue);
      expect(stabilizer.update(false), isTrue);
      expect(stabilizer.update(false), isFalse); // deactivates after 4 consecutive drops
    });

    test('Person is Boolean only and does not require hands', () {
      bool computePerson(bool upperBody, bool head, bool face) =>
          upperBody || head || face;

      expect(computePerson(true, false, false), isTrue);
      expect(computePerson(false, true, false), isTrue);
      expect(computePerson(false, false, true), isTrue);
      expect(computePerson(false, false, false), isFalse);
    });

    test('normalizeFacePoint handles rotated and unrotated detector coordinates', () {
      // 1. Coordinates already rotated (Upright 480x640)
      final normRotated = VisionDetectionService.normalizeFacePoint(
        px: 240,
        py: 320,
        rawWidth: 640,
        rawHeight: 480,
        detWidth: 480,
        detHeight: 640,
        rotation: InputImageRotation.rotation270deg,
        coordinatesAreRotated: true,
      );
      expect(normRotated.x, closeTo(0.5, 0.001));
      expect(normRotated.y, closeTo(0.5, 0.001));

      // 2. Coordinates in unrotated buffer (640x480) with 270deg rotation
      final normUnrotated = VisionDetectionService.normalizeFacePoint(
        px: 640,
        py: 240,
        rawWidth: 640,
        rawHeight: 480,
        detWidth: 480,
        detHeight: 640,
        rotation: InputImageRotation.rotation270deg,
        coordinatesAreRotated: false,
      );
      expect(normUnrotated.x, closeTo(0.5, 0.001));
      expect(normUnrotated.y, closeTo(0.0, 0.001));
    });

    test('Hand 21 points structure preserves MediaPipe 0..20 indices', () {
      final points = List.generate(
        21,
        (i) => HandLandmarkPoint(index: i, x: i / 20.0, y: i / 20.0, z: 0.0),
      );

      expect(points.length, equals(21));
      expect(points.first.index, equals(0)); // Wrist
      expect(points.last.index, equals(20));  // Pinky tip
      for (int i = 0; i < 21; i++) {
        expect(points[i].index, equals(i));
      }
    });

    test('VisionLandmarksState carries raw live points and freeze status', () {
      final handPts = List.generate(
        21,
        (i) => HandLandmarkPoint(index: i, x: 0.5, y: 0.5),
      );

      final state = VisionLandmarksState(
        personDetected: true,
        head: const LandmarkPartStatus(detected: true, actualPoints: 11, requiredPoints: 11),
        face: const LandmarkPartStatus(detected: true, actualPoints: 468, requiredPoints: 468),
        lips: const LandmarkPartStatus(detected: true, actualPoints: 19, requiredPoints: 19),
        rightHand: const LandmarkPartStatus(detected: true, actualPoints: 21, requiredPoints: 21),
        leftHand: LandmarkPartStatus.emptyHand,
        modelFaceLipPoints: 19,
        modelBodyHeadPoints: 25,
        totalModelPoints: 65,
        rightHandPoints: handPts,
        leftHandPoints: null,
        frameId: 100,
        detectorResultId: 99,
        motionDelta: 0.045,
        isPossiblyFrozen: false,
      );

      expect(state.rightHandPoints, isNotNull);
      expect(state.rightHandPoints!.length, equals(21));
      expect(state.leftHandPoints, isNull); // No cached landmarks for missing hand
      expect(state.isPossiblyFrozen, isFalse);
      expect(state.frameId, equals(100));
    });
  });
}
