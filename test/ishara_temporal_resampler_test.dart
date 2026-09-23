import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/ml/buffer/ishara_frame_ring_buffer.dart';
import 'package:ishara/ml/temporal/ishara_temporal_resampler.dart';

void main() {
  group('IsharaTemporalResampler Tests', () {
    test('resample 20 frames to 128 frames', () {
      final frames = List.generate(20, (i) {
        final data = Float32List(172);
        for (int k = 0; k < 172; k++) {
          data[k] = (i + 1).toDouble() * 0.01;
        }
        return IsharaBufferFrame(
          sequenceId: i,
          timestamp: DateTime.now().add(Duration(milliseconds: i * 33)),
          data: data,
          rawDetectedCount: 86,
          imputedCount: 0,
          isTrainingMatch: true,
        );
      });

      final resampled = IsharaTemporalResampler.resample(frames, durationMs: 660);

      expect(resampled.originalFrameCount, 20);
      expect(resampled.targetFrames, 128);
      expect(resampled.modelInput.flatData.length, 22016);
      expect(resampled.modelInput.shape, [1, 128, 86, 2]);

      // Verify that values interpolate smoothly from ~0.01 to ~0.20
      expect(resampled.modelInput.flatData[0], closeTo(0.01, 1e-4));
      expect(resampled.modelInput.flatData[22016 - 1], closeTo(0.20, 1e-4));
    });

    test('resample empty frames list handles gracefully', () {
      final resampled = IsharaTemporalResampler.resample([], durationMs: 0);
      expect(resampled.originalFrameCount, 0);
      expect(resampled.targetFrames, 128);
      expect(resampled.modelInput.flatData.length, 22016);
      expect(resampled.modelInput.shape, [1, 128, 86, 2]);
    });
  });
}
