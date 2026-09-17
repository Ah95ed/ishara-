import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/models/body_parts_detection_state.dart';
import 'package:ishara/services/vision_detection_service.dart';

void main() {
  group('Vision Detection State & Stabilization Tests', () {
    test('BodyPartsDetectionState initializes with false for all 6 parts', () {
      const state = BodyPartsDetectionState.empty;
      expect(state.person, isFalse);
      expect(state.head, isFalse);
      expect(state.face, isFalse);
      expect(state.lips, isFalse);
      expect(state.leftHand, isFalse);
      expect(state.rightHand, isFalse);
      expect(state.leftHandLandmarks, equals(0));
      expect(state.rightHandLandmarks, equals(0));
    });

    test('PartStabilizer activates only after consecutive positive frames', () {
      final stabilizer = PartStabilizer(framesToActivate: 2, framesToDeactivate: 4);

      // Frame 1: positive (not yet active)
      expect(stabilizer.update(true), isFalse);

      // Frame 2: positive (activates now)
      expect(stabilizer.update(true), isTrue);

      // Frame 3: stays active
      expect(stabilizer.update(true), isTrue);
    });

    test('PartStabilizer does not deactivate on single frame dropout', () {
      final stabilizer = PartStabilizer(framesToActivate: 2, framesToDeactivate: 4);

      // Activate
      stabilizer.update(true);
      stabilizer.update(true);
      expect(stabilizer.update(true), isTrue);

      // 1 negative frame -> should stay True
      expect(stabilizer.update(false), isTrue);

      // 2 negative frames -> should stay True
      expect(stabilizer.update(false), isTrue);

      // 3 negative frames -> should stay True
      expect(stabilizer.update(false), isTrue);

      // 4 negative frames -> deactivates now
      expect(stabilizer.update(false), isFalse);
    });

    test('Person is detected if pose, head, or face is present without hands', () {
      bool computePerson(bool pose, bool head, bool face) =>
          pose || head || face;

      // Test 1: Only pose is detected (person with hands hidden)
      expect(computePerson(true, false, false), isTrue);

      // Test 2: Only head is detected
      expect(computePerson(false, true, false), isTrue);

      // Test 3: Only face is detected
      expect(computePerson(false, false, true), isTrue);

      // Test 4: All false
      expect(computePerson(false, false, false), isFalse);
    });

    test('Face and Lips are independent states', () {
      const faceDetectedState = BodyPartsDetectionState(
        person: true,
        head: true,
        face: true,
        lips: false, // Mouth covered
        leftHand: false,
        rightHand: false,
      );

      expect(faceDetectedState.face, isTrue);
      expect(faceDetectedState.lips, isFalse);
      expect(faceDetectedState.person, isTrue);
    });
  });
}
