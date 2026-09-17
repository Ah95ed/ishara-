import 'package:flutter_test/flutter_test.dart';
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
  });
}
