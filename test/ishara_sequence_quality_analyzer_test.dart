import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/ml/analyzer/ishara_sequence_quality_analyzer.dart';
import 'package:ishara/ml/buffer/ishara_frame_ring_buffer.dart';
import 'package:ishara/ml/preprocessing/ishara_normalizer.dart';

void main() {
  group('Sequence Quality Analyzer & FrameMetadata Tests', () {
    test('Test 1: FrameMetadata properties and counts', () {
      final meta = FrameMetadata(
        frameId: 345,
        timestamp: DateTime(2026, 9, 19, 10, 0, 0),
        rightHandRawCount: 21,
        leftHandRawCount: 0,
        lipsRawCount: 19,
        bodyRawCount: 25,
        rawValidPoints: 65,
        imputedPoints: 21,
      );

      expect(meta.isRightHandRawValid, true);
      expect(meta.isLeftHandRawValid, false);
      expect(meta.isLipsRawValid, true);
      expect(meta.isBodyRawValid, true);
      expect(meta.hasAtLeastOneHand, true);
      expect(meta.hasBothHands, false);
      expect(meta.hasNoHands, false);
      expect(meta.isFullyRawComplete, false);
    });

    test('Test 2: SequenceQualityAnalyzer 128 frames metrics and text report', () {
      final List<FrameMetadata> metadataList = [];
      final startTime = DateTime(2026, 9, 19, 12, 0, 0);

      for (int i = 0; i < 128; i++) {
        final int rhCount = i >= 10 ? 21 : 0;
        final int lhCount = (i >= 20 && !(i >= 60 && i <= 75)) ? 21 : 0;
        const int lipsCount = 19;
        const int bodyCount = 25;

        final int rawValid = rhCount + lhCount + lipsCount + bodyCount;
        final int imputed = 86 - rawValid;

        metadataList.add(FrameMetadata(
          frameId: i + 1,
          timestamp: startTime.add(Duration(milliseconds: i * 66)), // ~15 FPS
          rightHandRawCount: rhCount,
          leftHandRawCount: lhCount,
          lipsRawCount: lipsCount,
          bodyRawCount: bodyCount,
          rawValidPoints: rawValid,
          imputedPoints: imputed,
        ));
      }

      final report = IsharaSequenceQualityAnalyzer.analyzeFrames(
        metadataList: metadataList,
        capacity: 128,
        captureTime: startTime.add(const Duration(seconds: 10)),
      );

      expect(report.frameCount, 128);
      expect(report.totalPossiblePoints, 11008);
      expect(report.rhInitialMissing, 10);
      expect(report.lhInitialMissing, 20);
      expect(report.lipsInitialMissing, 0);
      expect(report.bodyInitialMissing, 0);
      expect(report.lhLongestMissingRun, 20);
      expect(report.isChronologicalOrder, true);
      expect(report.duplicateCount, 0);
      expect(report.averageFrameIntervalMs.round(), 66);

      // Check report text generation
      final reportText = report.toClipboardReportText();
      expect(reportText.contains('ISHARA SEQUENCE QUALITY REPORT'), true);
      expect(reportText.contains('Buffer:\n128/128'), true);
      expect(reportText.contains('SEQUENCE DATA QUALITY:'), true);
      expect(reportText.contains('Metric:\nRaw Keypoint Coverage'), true);
      expect(reportText.contains('RIGHT HAND'), true);
      expect(reportText.contains('LEFT HAND'), true);
      expect(reportText.contains('HAND AVAILABILITY'), true);
      expect(reportText.contains('QUALITY NOTES'), true);
      expect(reportText.contains('It is NOT model accuracy.'), true);
      expect(reportText.contains('No inference was executed.'), true);
    });

    test('Test 3: Ring Buffer integration and metadata preservation in sliding window', () {
      final ringBuffer = IsharaFrameRingBuffer();
      final startTime = DateTime(2026, 9, 19, 14, 0, 0);

      for (int i = 1; i <= 130; i++) {
        final points = List.generate(86, (idx) => Point2D(0.5, 0.5));
        final isRh = i > 5;
        final isLh = i > 15;

        ringBuffer.addFrame(
          normalizedPoints: points,
          timestamp: startTime.add(Duration(milliseconds: i * 50)),
          personPresent: true,
          rawDetectedCount: (isRh ? 21 : 0) + (isLh ? 21 : 0) + 19 + 25,
          imputedCount: 86 - ((isRh ? 21 : 0) + (isLh ? 21 : 0) + 19 + 25),
          rightHandRawCount: isRh ? 21 : 0,
          leftHandRawCount: isLh ? 21 : 0,
          lipsRawCount: 19,
          bodyRawCount: 25,
          frameId: i,
        );
      }

      expect(ringBuffer.count, 128);
      final status = ringBuffer.getStatus();
      expect(status.isReady, true);
      expect(status.qualityReport != null, true);
      expect(status.qualityReport!.frameCount, 128);

      // In sliding window from 3..130:
      // Frame 3..5: RH missing (3 frames: 3, 4, 5).
      expect(status.qualityReport!.rhInitialMissing, 3);
    });
  });
}
