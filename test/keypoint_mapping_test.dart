import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/keypoints/ishara_keypoint_mapper.dart';
import 'package:ishara/keypoints/keypoint_normalizer.dart';
import 'package:ishara/keypoints/keypoint_validator.dart';
import 'package:ishara/models/body_parts_detection_state.dart';

void main() {
  group('IsharaKeypointMapper & Training Dataset Specification Tests', () {
    test('Verified indices strictly match datasetv2.py specification', () {
      // 1. Right Hand: 21 points (0..20)
      expect(IsharaKeypointMapper.numRightHand, equals(21));

      // 2. Left Hand: 21 points (21..41)
      expect(IsharaKeypointMapper.numLeftHand, equals(21));

      // 3. Lips: 19 deduplicated sorted points (42..60)
      expect(IsharaKeypointMapper.numLips, equals(19));
      expect(
        IsharaKeypointMapper.lipMeshIndices,
        equals([
          0, 17, 37, 39, 40, 61, 84, 91, 146, 181,
          185, 267, 269, 270, 291, 314, 321, 375, 405
        ]),
      );

      // 4. Body & Head: 25 points (61..85)
      expect(IsharaKeypointMapper.numBody, equals(25));
      expect(
        IsharaKeypointMapper.upperBodyIndices,
        equals(List.generate(25, (i) => i)),
      );

      // Total keypoints: exactly 86
      expect(IsharaKeypointMapper.totalKeypoints, equals(86));
    });

    test('extractRawModelKeypoints produces exact [86, 2] matrix and Float32List', () {
      final rightHand = List.generate(
        21,
        (i) => HandLandmarkPoint(index: i, x: 0.1 + i * 0.01, y: 0.2 + i * 0.01),
      );
      final leftHand = List.generate(
        21,
        (i) => HandLandmarkPoint(index: i, x: 0.5 + i * 0.01, y: 0.6 + i * 0.01),
      );
      final lips = List.generate(
        19,
        (i) => NormalizedPoint(0.3 + i * 0.01, 0.4 + i * 0.01),
      );
      final pose = List.generate(
        25,
        (i) => PoseLandmarkPoint(index: i, x: 0.4 + i * 0.01, y: 0.5 + i * 0.01),
      );

      final frame = IsharaKeypointMapper.extractRawModelKeypoints(
        rightHand: rightHand,
        leftHand: leftHand,
        lipsPoints: lips,
        posePoints: pose,
      );

      expect(frame.keypoints.length, equals(86));
      expect(frame.validCount, equals(86));
      expect(frame.missingCount, equals(0));
      expect(frame.nanCount, equals(0));
      expect(frame.infCount, equals(0));
      expect(frame.isTrainingMappingVerified, isTrue);

      final matrix = frame.toMatrix();
      expect(matrix.length, equals(86));
      for (final row in matrix) {
        expect(row.length, equals(2));
      }

      final flatArr = frame.toFlatArray();
      expect(flatArr.length, equals(172)); // 86 * 2
    });

    test('Missing hand results in exact partial count without faking 86/86', () {
      // Only Left Hand, Lips, Body detected (Right Hand missing)
      final leftHand = List.generate(
        21,
        (i) => HandLandmarkPoint(index: i, x: 0.5, y: 0.6),
      );
      final lips = List.generate(
        19,
        (i) => NormalizedPoint(0.3, 0.4),
      );
      final pose = List.generate(
        25,
        (i) => PoseLandmarkPoint(index: i, x: 0.4, y: 0.5),
      );

      final frame = IsharaKeypointMapper.extractRawModelKeypoints(
        rightHand: null,
        leftHand: leftHand,
        lipsPoints: lips,
        posePoints: pose,
      );

      expect(frame.keypoints.length, equals(86));
      expect(frame.validCount, equals(65)); // 86 - 21 = 65
      expect(frame.missingCount, equals(21));

      final validation = KeypointValidator.validate(frame);
      expect(validation.validCount, equals(65));
      expect(validation.missingCount, equals(21));
      expect(validation.validRightHandPoints, equals(0));
      expect(validation.validLeftHandPoints, equals(21));
      expect(validation.validFaceLipPoints, equals(19));
      expect(validation.validBodyHeadPoints, equals(25));
      expect(validation.isFullyDetected, isFalse);
    });

    test('KeypointValidator rejects NaN and Infinity', () {
      final keypoints = List.generate(86, (i) {
        if (i == 5) {
          return ModelKeypointInfo(
            modelIndex: i,
            source: ModelKeypointSource.rightHand,
            sourceIndex: 5,
            description: 'NaN test',
            x: double.nan,
            y: 0.5,
          );
        }
        if (i == 10) {
          return ModelKeypointInfo(
            modelIndex: i,
            source: ModelKeypointSource.rightHand,
            sourceIndex: 10,
            description: 'Inf test',
            x: 0.5,
            y: double.infinity,
          );
        }
        return ModelKeypointInfo(
          modelIndex: i,
          source: ModelKeypointSource.rightHand,
          sourceIndex: i,
          description: 'Valid',
          x: 0.5,
          y: 0.5,
        );
      });

      final frame = KeypointFrame(
        keypoints: keypoints,
        timestamp: DateTime.now(),
      );

      final validation = KeypointValidator.validate(frame);
      expect(validation.nanCount, equals(1));
      expect(validation.infCount, equals(1));
      expect(validation.hasInvalidNumbers, isTrue);
      expect(validation.isFullyDetected, isFalse);
    });

    test('Motion detection calculates moving points between frames', () {
      final frame1 = IsharaKeypointMapper.extractRawModelKeypoints(
        rightHand: List.generate(21, (i) => HandLandmarkPoint(index: i, x: 0.1, y: 0.1)),
        leftHand: List.generate(21, (i) => HandLandmarkPoint(index: i, x: 0.5, y: 0.5)),
        lipsPoints: List.generate(19, (i) => const NormalizedPoint(0.3, 0.3)),
        posePoints: List.generate(25, (i) => PoseLandmarkPoint(index: i, x: 0.4, y: 0.4)),
      );

      // Move right hand in frame 2
      final frame2 = IsharaKeypointMapper.extractRawModelKeypoints(
        rightHand: List.generate(21, (i) => HandLandmarkPoint(index: i, x: 0.2, y: 0.2)), // moved!
        leftHand: List.generate(21, (i) => HandLandmarkPoint(index: i, x: 0.5, y: 0.5)),
        lipsPoints: List.generate(19, (i) => const NormalizedPoint(0.3, 0.3)),
        posePoints: List.generate(25, (i) => PoseLandmarkPoint(index: i, x: 0.4, y: 0.4)),
      );

      final val = KeypointValidator.validate(frame2, previousFrame: frame1);
      expect(val.movingPointsCount, equals(21)); // exactly the 21 right hand points moved
      expect(val.totalMovementDistance, greaterThan(0.0));
    });

    test('KeypointNormalizer normalizes within [-0.5, 0.5] range as in datasetv2.py', () {
      final sampleSubset = [
        [100.0, 150.0],
        [120.0, 160.0],
        [140.0, 180.0],
        [110.0, 140.0],
      ];

      final normalized = KeypointNormalizer.normalizeSubset(sampleSubset);
      expect(normalized.length, equals(4));

      for (final pt in normalized) {
        expect(pt[0], inInclusiveRange(-0.5, 0.5));
        expect(pt[1], inInclusiveRange(-0.5, 0.5));
      }
    });
  });
}
