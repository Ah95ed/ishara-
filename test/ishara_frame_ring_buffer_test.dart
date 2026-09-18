import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/ml/buffer/ishara_buffer_validator.dart';
import 'package:ishara/ml/buffer/ishara_frame_ring_buffer.dart';
import 'package:ishara/ml/preprocessing/ishara_normalizer.dart';

void main() {
  group('IsharaFrameRingBuffer Architecture & Parity Tests', () {
    late IsharaFrameRingBuffer buffer;

    setUp(() {
      buffer = IsharaFrameRingBuffer();
    });

    List<Point2D> makeSyntheticFrame(double fillValue) {
      return List.generate(86, (i) => Point2D(fillValue, fillValue));
    }

    test('Initial state is EMPTY with 0 frames', () {
      final status = buffer.getStatus();
      expect(status.frameCount, 0);
      expect(status.capacity, 128);
      expect(status.state, RingBufferState.paused); // person absent initially
      expect(buffer.isReady, false);
    });

    test('Requirement #19: Ring buffer overwrite and chronological order test', () {
      final startTime = DateTime(2026, 1, 1, 12, 0, 0);

      // Add Frames 1 to 128
      for (int i = 1; i <= 128; i++) {
        final ok = buffer.addFrame(
          normalizedPoints: makeSyntheticFrame(i.toDouble()),
          timestamp: startTime.add(Duration(milliseconds: i * 50)),
          personPresent: true,
        );
        expect(ok, true, reason: 'Frame $i should be added');
      }

      expect(buffer.count, 128);
      expect(buffer.isReady, true);
      expect(buffer.state, RingBufferState.ready);

      // Verify Chronological ordering 1..128
      var frames = buffer.getChronologicalFrames();
      expect(frames.length, 128);
      expect(frames.first.sequenceId, 1);
      expect(frames.first.data[0], 1.0);
      expect(frames.last.sequenceId, 128);
      expect(frames.last.data[0], 128.0);

      // Add Frame 129
      final ok129 = buffer.addFrame(
        normalizedPoints: makeSyntheticFrame(129.0),
        timestamp: startTime.add(const Duration(milliseconds: 129 * 50)),
        personPresent: true,
      );
      expect(ok129, true);
      expect(buffer.count, 128, reason: 'Buffer capacity must stay at 128');

      // Now oldest should be 2, newest should be 129
      frames = buffer.getChronologicalFrames();
      expect(frames.length, 128);
      expect(frames.first.sequenceId, 2, reason: 'Oldest frame after 129 must be 2');
      expect(frames.first.data[0], 2.0);
      expect(frames.last.sequenceId, 129, reason: 'Newest frame must be 129');
      expect(frames.last.data[0], 129.0);

      // Add Frame 130
      final ok130 = buffer.addFrame(
        normalizedPoints: makeSyntheticFrame(130.0),
        timestamp: startTime.add(const Duration(milliseconds: 130 * 50)),
        personPresent: true,
      );
      expect(ok130, true);
      expect(buffer.count, 128);

      // Now oldest should be 3, newest should be 130
      frames = buffer.getChronologicalFrames();
      expect(frames.first.sequenceId, 3, reason: 'Oldest frame after 130 must be 3');
      expect(frames.first.data[0], 3.0);
      expect(frames.last.sequenceId, 130, reason: 'Newest frame must be 130');
      expect(frames.last.data[0], 130.0);

      // Verify monotonic increment of all 128 frames
      for (int i = 0; i < 128; i++) {
        expect(frames[i].sequenceId, 3 + i);
        expect(frames[i].data[0], (3 + i).toDouble());
      }
    });

    test('Requirement #20: Deep copy verification (mutation isolation)', () {
      final points = List<Point2D>.generate(86, (i) => const Point2D(1.0, 1.0));
      final time = DateTime.now();

      buffer.addFrame(
        normalizedPoints: points,
        timestamp: time,
        personPresent: true,
      );

      // Mutate the original list
      points[0] = const Point2D(999.0, 999.0);

      // Read from buffer
      final frames = buffer.getChronologicalFrames();
      expect(frames.first.data[0], 1.0, reason: 'Buffer data must remain 1.0 and not 999.0');
      expect(frames.first.data[1], 1.0);
    });

    test('Requirement #7: Duplicate timestamp rejection', () {
      final time = DateTime(2026, 1, 1, 12, 0, 0);

      final ok1 = buffer.addFrame(
        normalizedPoints: makeSyntheticFrame(1.0),
        timestamp: time,
        personPresent: true,
      );
      expect(ok1, true);

      // Attempt to add with the EXACT same timestamp
      final ok2 = buffer.addFrame(
        normalizedPoints: makeSyntheticFrame(2.0),
        timestamp: time,
        personPresent: true,
      );
      expect(ok2, false, reason: 'Duplicate timestamp must be rejected');
      expect(buffer.duplicateFramesRejected, 1);
      expect(buffer.count, 1);

      // Attempt to add with an OLDER timestamp
      final ok3 = buffer.addFrame(
        normalizedPoints: makeSyntheticFrame(3.0),
        timestamp: time.subtract(const Duration(milliseconds: 100)),
        personPresent: true,
      );
      expect(ok3, false, reason: 'Stale/older timestamp must be rejected');
      expect(buffer.duplicateFramesRejected, 2);
      expect(buffer.count, 1);
    });

    test('Requirement #8: Person absent pause behavior', () {
      final time = DateTime(2026, 1, 1, 12, 0, 0);

      // Frame with person
      buffer.addFrame(
        normalizedPoints: makeSyntheticFrame(1.0),
        timestamp: time,
        personPresent: true,
      );
      expect(buffer.count, 1);
      expect(buffer.state, RingBufferState.filling);

      // Frame with NO person
      final okNoPerson = buffer.addFrame(
        normalizedPoints: makeSyntheticFrame(2.0),
        timestamp: time.add(const Duration(milliseconds: 50)),
        personPresent: false,
      );
      expect(okNoPerson, false);
      expect(buffer.count, 1, reason: 'Buffer count should not increase when person is absent');
      expect(buffer.state, RingBufferState.paused);
      expect(buffer.totalFramesSkippedNoPerson, 1);

      // Person returns
      final okPersonReturns = buffer.addFrame(
        normalizedPoints: makeSyntheticFrame(3.0),
        timestamp: time.add(const Duration(milliseconds: 100)),
        personPresent: true,
      );
      expect(okPersonReturns, true);
      expect(buffer.count, 2);
      expect(buffer.state, RingBufferState.filling);
    });

    test('Requirement #10: Hands backward fill on snapshot copy ONLY', () {
      final time = DateTime(2026, 1, 1, 12, 0, 0);

      // Build 128 frames:
      // Frames 0..4 have all-zero hands (RightHand 0..20, LeftHand 21..41)
      // Frame 5 has non-zero hands: RightHand = 0.45, LeftHand = 0.55
      for (int i = 0; i < 128; i++) {
        final pts = List<Point2D>.generate(86, (k) {
          if (k < 42) {
            // Hands
            return i < 5 ? const Point2D(0.0, 0.0) : Point2D(0.45, 0.55);
          } else {
            // Lips and Body
            return Point2D(0.1 * (k % 5), 0.2);
          }
        });

        buffer.addFrame(
          normalizedPoints: pts,
          timestamp: time.add(Duration(milliseconds: i * 40)),
          personPresent: true,
        );
      }

      expect(buffer.count, 128);

      // Check live buffer at index 0 before snapshot: hands are zeros
      final liveFramesBefore = buffer.getChronologicalFrames();
      expect(liveFramesBefore[0].data[0], 0.0);
      expect(liveFramesBefore[0].data[42], 0.0);

      // Build Model Input Sequence with backward fill
      final modelSeq = buffer.buildModelInput(applyHandsBackwardFill: true);
      expect(modelSeq, isNotNull);
      expect(modelSeq!.shape, [1, 128, 86, 2]);
      expect(modelSeq.flatData.length, 22016);
      expect(modelSeq.hasBackwardFilledHands, true);

      // In the output sequence, frame 0 should now have the filled hands!
      // RightHand X at index 0 should be 0.45
      // LeftHand X at index 42 should be 0.45
      expect(modelSeq.flatData[0], closeTo(0.45, 1e-6), reason: 'Frame 0 Right Hand must be backward-filled');
      expect(modelSeq.flatData[1], closeTo(0.55, 1e-6));
      expect(modelSeq.flatData[42], closeTo(0.45, 1e-6), reason: 'Frame 0 Left Hand must be backward-filled');
      expect(modelSeq.flatData[43], closeTo(0.55, 1e-6));

      // CRITICAL: Ensure live ring buffer was NOT mutated!
      final liveFramesAfter = buffer.getChronologicalFrames();
      expect(liveFramesAfter[0].data[0], 0.0, reason: 'Live buffer frame 0 must remain 0.0 (untouched)');
      expect(liveFramesAfter[0].data[42], 0.0, reason: 'Live buffer frame 0 must remain 0.0 (untouched)');
    });

    test('Requirement #15: Frame validation & NaN / Inf rejection', () {
      final time = DateTime.now();

      // NaN point
      final nanPoints = List<Point2D>.generate(86, (i) => Point2D(i == 10 ? double.nan : 0.5, 0.5));
      final okNan = buffer.addFrame(
        normalizedPoints: nanPoints,
        timestamp: time,
        personPresent: true,
      );
      expect(okNan, false);
      expect(buffer.invalidFramesRejected, 1);

      // Inf point
      final infPoints = List<Point2D>.generate(86, (i) => Point2D(0.5, i == 20 ? double.infinity : 0.5));
      final okInf = buffer.addFrame(
        normalizedPoints: infPoints,
        timestamp: time.add(const Duration(milliseconds: 10)),
        personPresent: true,
      );
      expect(okInf, false);
      expect(buffer.invalidFramesRejected, 2);

      // Invalid length (not 86)
      final shortPoints = List<Point2D>.generate(50, (i) => const Point2D(0.5, 0.5));
      final okShort = buffer.addFrame(
        normalizedPoints: shortPoints,
        timestamp: time.add(const Duration(milliseconds: 20)),
        personPresent: true,
      );
      expect(okShort, false);
      expect(buffer.invalidFramesRejected, 3);
    });

    test('Snapshot validation report via IsharaBufferValidator', () {
      final time = DateTime(2026, 1, 1, 12, 0, 0);

      for (int i = 1; i <= 128; i++) {
        buffer.addFrame(
          normalizedPoints: makeSyntheticFrame(i.toDouble()),
          timestamp: time.add(Duration(milliseconds: i * 30)),
          personPresent: true,
        );
      }

      final frames = buffer.getChronologicalFrames();
      final report = IsharaBufferValidator.validateSnapshot(
        frames: frames.map((f) => f.data).toList(),
        sequenceIds: frames.map((f) => f.sequenceId).toList(),
        capacity: 128,
      );

      expect(report.isValid, true);
      expect(report.nanCount, 0);
      expect(report.infCount, 0);
      expect(report.duplicateCount, 0);
      expect(report.isChronologicallyOrdered, true);
      expect(report.sequenceShape, [128, 86, 2]);
      expect(report.modelShape, [1, 128, 86, 2]);
    });
  });
}
