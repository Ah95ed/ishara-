import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/ml/preprocessing/ishara_normalizer.dart';

void main() {
  group('IsharaNormalizer Numerical Parity & Python DatasetV2 Match Tests', () {
    test('Test vector numerical parity with NumPy datasetv2.py (tolerance 1e-5)', () {
      // Vector from user requirement #21:
      // [[0.20, 0.30], [0.40, 0.50], [0.60, 0.20]]
      final testVector = [
        const Point2D(0.20, 0.30),
        const Point2D(0.40, 0.50),
        const Point2D(0.60, 0.20),
      ];

      final result = IsharaNormalizer.normalizeRawPoints(
        testVector,
        groupName: 'UnitTestVector',
      );

      final diag = result.diagnostic;

      // 1. Check Origin
      expect(diag.referenceOrigin.x, closeTo(0.20, 1e-6));
      expect(diag.referenceOrigin.y, closeTo(0.30, 1e-6));

      // 2. Check Min X and Y
      // After pose -= pose[0]:
      // P0 = (0, 0), P1 = (0.20, 0.20), P2 = (0.40, -0.10)
      // minX = 0.0, minY = -0.10
      expect(diag.minX, closeTo(0.0, 1e-6));
      expect(diag.minY, closeTo(-0.10, 1e-6));

      // 3. Check Scale = max(maxX, maxY)
      // After pose -= min:
      // P0 = (0, 0.10), P1 = (0.20, 0.30), P2 = (0.40, 0)
      // maxX = 0.40, maxY = 0.30 -> Scale = 0.40
      expect(diag.scale, closeTo(0.40, 1e-6));

      // 4. Check Global Mean (scalar over all 6 values)
      // After pose /= scale:
      // P0 = (0, 0.25), P1 = (0.50, 0.75), P2 = (1.00, 0)
      // Sum = 2.50 -> Mean = 2.50 / 6 = 5/12 ≈ 0.4166667
      expect(diag.globalMean, closeTo(5.0 / 12.0, 1e-6));

      // 5. Check MaxAbs
      // After pose -= mean:
      // Values: -5/12, -2/12, 1/12, 4/12, 7/12, -5/12
      // MaxAbs = 7/12 ≈ 0.5833333
      expect(diag.maxAbs, closeTo(7.0 / 12.0, 1e-6));

      // 6. Check Final Normalized Points against Exact Python Fractions
      // P0 = [-5/14, -2/14] ≈ [-0.357142857, -0.142857143]
      // P1 = [ 1/14,  4/14] ≈ [ 0.071428571,  0.285714286]
      // P2 = [ 7/14, -5/14] = [ 0.5,         -0.357142857]
      final expectedP0 = const Point2D(-5.0 / 14.0, -2.0 / 14.0);
      final expectedP1 = const Point2D(1.0 / 14.0, 4.0 / 14.0);
      final expectedP2 = const Point2D(7.0 / 14.0, -5.0 / 14.0);

      final pts = result.points;
      expect(pts.length, equals(3));

      expect(pts[0].x, closeTo(expectedP0.x, 1e-5));
      expect(pts[0].y, closeTo(expectedP0.y, 1e-5));

      expect(pts[1].x, closeTo(expectedP1.x, 1e-5));
      expect(pts[1].y, closeTo(expectedP1.y, 1e-5));

      expect(pts[2].x, closeTo(expectedP2.x, 1e-5));
      expect(pts[2].y, closeTo(expectedP2.y, 1e-5));

      // Check range is within [-0.5, 0.5]
      for (final p in pts) {
        expect(p.x, inInclusiveRange(-0.5, 0.5));
        expect(p.y, inInclusiveRange(-0.5, 0.5));
      }
    });

    test('Each group normalized independently and concatenated into exact [86, 2]', () {
      final normalizer = IsharaNormalizer();

      final rh = List.generate(21, (i) => Point2D(0.1 + i * 0.01, 0.2 + i * 0.01));
      final lh = List.generate(21, (i) => Point2D(0.5 + i * 0.01, 0.6 + i * 0.01));
      final lips = List.generate(19, (i) => Point2D(0.3 + i * 0.01, 0.4 + i * 0.01));
      final body = List.generate(25, (i) => Point2D(0.4 + i * 0.01, 0.5 + i * 0.01));

      final frameResult = normalizer.processFrame(
        rawRightHand: rh,
        rawLeftHand: lh,
        rawLips: lips,
        rawBody: body,
      );

      expect(frameResult.all86Keypoints.length, equals(86));
      expect(frameResult.validNormalizedCount, equals(86));
      expect(frameResult.nanCount, equals(0));
      expect(frameResult.infCount, equals(0));
      expect(frameResult.isTrainingMatch, isTrue);

      final matrix = frameResult.toMatrix();
      expect(matrix.length, equals(86));
      for (final row in matrix) {
        expect(row.length, equals(2));
      }

      final flat = frameResult.toFlatFloat32List();
      expect(flat.length, equals(172));
    });

    test('Missing group uses previous valid frame without mutating original lists', () {
      final normalizer = IsharaNormalizer();

      final rh = List.generate(21, (i) => Point2D(0.1 + i * 0.01, 0.2 + i * 0.01));
      final lh = List.generate(21, (i) => Point2D(0.5 + i * 0.01, 0.6 + i * 0.01));
      final lips = List.generate(19, (i) => Point2D(0.3 + i * 0.01, 0.4 + i * 0.01));
      final body = List.generate(25, (i) => Point2D(0.4 + i * 0.01, 0.5 + i * 0.01));

      // Frame 1: all detected
      final frame1 = normalizer.processFrame(
        rawRightHand: rh,
        rawLeftHand: lh,
        rawLips: lips,
        rawBody: body,
      );
      expect(frame1.validNormalizedCount, equals(86));

      // Frame 2: Right hand missing
      final frame2 = normalizer.processFrame(
        rawRightHand: null, // missing!
        rawLeftHand: lh,
        rawLips: lips,
        rawBody: body,
      );

      // Carried forward from previous
      expect(frame2.rightHand.length, equals(21));
      expect(frame2.rightHand, equals(frame1.rightHand));
      expect(frame2.rightHandDiag.failureReason, equals('GROUP_MISSING_USED_PREVIOUS_FRAME'));
    });

    test('Division by zero protection handles degenerate points with epsilon guard', () {
      final degeneratePoints = List.generate(21, (_) => const Point2D(0.5, 0.5));
      final result = IsharaNormalizer.normalizeRawPoints(
        degeneratePoints,
        groupName: 'DegenerateTest',
      );

      expect(result.diagnostic.isDegenerate, isTrue);
      expect(result.diagnostic.failureReason, equals('NORMALIZATION_INVALID_SCALE'));
      expect(result.points.length, equals(21));
      for (final p in result.points) {
        expect(p.isValid, isTrue);
        expect(p.x, equals(0.0));
        expect(p.y, equals(0.0));
      }
    });
  });
}
