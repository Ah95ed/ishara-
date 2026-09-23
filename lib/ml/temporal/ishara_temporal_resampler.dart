import 'dart:typed_data';
import 'package:ishara/keypoints/ishara_keypoint_mapper.dart';
import 'package:ishara/ml/buffer/ishara_frame_ring_buffer.dart';

/// نتيجة الاستيفاء الزمني الذكي لمقاطع لغة الإشارة
class ResampledSignSequence {
  final int originalFrameCount;
  final int originalDurationMs;
  final double originalFps;
  final int targetFrames; // 128
  final ModelInputSequence modelInput;

  const ResampledSignSequence({
    required this.originalFrameCount,
    required this.originalDurationMs,
    required this.originalFps,
    this.targetFrames = 128,
    required this.modelInput,
  });
}

/// مستوفي الإشارات الزمني (IsharaTemporalResampler)
/// يستوفي مقاطع الإشارات الطبيعية (سواء كانت 20 أو 40 أو 80 فريم)
/// بدقة رياضية خطية على المحور الزمني t in [0, 1] لتوليد مصفوفة [1, 128, 86, 2]
/// مما يتيح أداء الإشارة بالسرعة الطبيعية فوراً دون انتظار 128 إطار كاميرا.
class IsharaTemporalResampler {
  static const int targetFrames = 128;
  static const int totalKeypoints = IsharaKeypointMapper.totalKeypoints; // 86
  static const int coordsPerPoint = 2; // (x, y)
  static const int valuesPerFrame = totalKeypoints * coordsPerPoint; // 172
  static const int totalValues = targetFrames * valuesPerFrame; // 22016

  /// استيفاء قائمة إطارات الإشارة الأصلية إلى 128 إطاراً
  static ResampledSignSequence resample(
    List<IsharaBufferFrame> frames, {
    int durationMs = 0,
  }) {
    final int n = frames.length;
    final flatData = Float32List(totalValues);
    final double fps = durationMs > 0 ? (n * 1000.0) / durationMs : 30.0;

    if (n == 0) {
      final input = ModelInputSequence(
        flatData: flatData,
        shape: const [1, targetFrames, totalKeypoints, coordsPerPoint],
        oldestFrameSequenceId: 0,
        newestFrameSequenceId: 0,
        nanCount: 0,
        infCount: 0,
        hasBackwardFilledHands: false,
        frameCount: 0,
      );
      return ResampledSignSequence(
        originalFrameCount: 0,
        originalDurationMs: durationMs,
        originalFps: 0.0,
        modelInput: input,
      );
    }

    if (n == 1) {
      // تكرار الإطار الوحيد عبر الـ 128 إطاراً
      final singleFlat = frames.first.data;
      for (int t = 0; t < targetFrames; t++) {
        flatData.setRange(t * valuesPerFrame, (t + 1) * valuesPerFrame, singleFlat);
      }
      final input = ModelInputSequence(
        flatData: flatData,
        shape: const [1, targetFrames, totalKeypoints, coordsPerPoint],
        oldestFrameSequenceId: frames.first.sequenceId,
        newestFrameSequenceId: frames.first.sequenceId,
        nanCount: 0,
        infCount: 0,
        hasBackwardFilledHands: false,
        frameCount: 1,
      );
      return ResampledSignSequence(
        originalFrameCount: 1,
        originalDurationMs: durationMs,
        originalFps: fps,
        modelInput: input,
      );
    }

    // استخراج المصفوفات المسطحة مسبقاً
    final flatFrames = List.generate(n, (i) => frames[i].data);

    // استيفاء خطي منتظم عبر المحور الزمني t
    for (int targetIdx = 0; targetIdx < targetFrames; targetIdx++) {
      final double relPos = (targetIdx / (targetFrames - 1)) * (n - 1);
      final int leftIdx = relPos.floor().clamp(0, n - 2);
      final int rightIdx = (leftIdx + 1).clamp(0, n - 1);
      final double fraction = relPos - leftIdx;

      final leftFrame = flatFrames[leftIdx];
      final rightFrame = flatFrames[rightIdx];
      final int offset = targetIdx * valuesPerFrame;

      for (int k = 0; k < valuesPerFrame; k++) {
        final double valL = leftFrame[k];
        final double valR = rightFrame[k];
        flatData[offset + k] = valL + (valR - valL) * fraction;
      }
    }

    final input = ModelInputSequence(
      flatData: flatData,
      shape: const [1, targetFrames, totalKeypoints, coordsPerPoint],
      oldestFrameSequenceId: frames.first.sequenceId,
      newestFrameSequenceId: frames.last.sequenceId,
      nanCount: 0,
      infCount: 0,
      hasBackwardFilledHands: false,
      frameCount: targetFrames,
    );

    return ResampledSignSequence(
      originalFrameCount: n,
      originalDurationMs: durationMs,
      originalFps: fps,
      modelInput: input,
    );
  }
}
