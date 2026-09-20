import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/ml/ctc/ishara_ctc_decoder.dart';

void main() {
  group('IsharaCtcDecoder Unit Tests (Mandatory Specification)', () {
    test('TEST 1: [0,0,5,5,5,0,9,9,0] -> [5,9]', () {
      final res = IsharaCtcDecoder.decodeRawArgmax([0, 0, 5, 5, 5, 0, 9, 9, 0]);
      expect(res.decodedIds, [5, 9]);
      expect(res.blankTimesteps, 4);
      expect(res.collapsedDuplicateCount, 3);
      expect(res.decodedLength, 2);
    });

    test('TEST 2: [5,5,0,5,5] -> [5,5] (Blank separates consecutive duplicates)', () {
      final res = IsharaCtcDecoder.decodeRawArgmax([5, 5, 0, 5, 5]);
      expect(res.decodedIds, [5, 5]);
      expect(res.blankTimesteps, 1);
      expect(res.collapsedDuplicateCount, 2);
      expect(res.decodedLength, 2);
      expect(res.positions[0].timestep, 0);
      expect(res.positions[1].timestep, 3);
    });

    test('TEST 3: [0,0,0,0] -> []', () {
      final res = IsharaCtcDecoder.decodeRawArgmax([0, 0, 0, 0]);
      expect(res.decodedIds, isEmpty);
      expect(res.blankTimesteps, 4);
      expect(res.collapsedDuplicateCount, 0);
      expect(res.decodedLength, 0);
    });

    test('TEST 4: [1,2,3] -> [1,2,3]', () {
      final res = IsharaCtcDecoder.decodeRawArgmax([1, 2, 3]);
      expect(res.decodedIds, [1, 2, 3]);
      expect(res.blankTimesteps, 0);
      expect(res.collapsedDuplicateCount, 0);
      expect(res.decodedLength, 3);
    });

    test('TEST 5: [4,4,4,4] -> [4]', () {
      final res = IsharaCtcDecoder.decodeRawArgmax([4, 4, 4, 4]);
      expect(res.decodedIds, [4]);
      expect(res.blankTimesteps, 0);
      expect(res.collapsedDuplicateCount, 3);
      expect(res.decodedLength, 1);
    });

    test('Self-tests runner returns true', () {
      expect(IsharaCtcDecoder.runSelfTests(), isTrue);
    });

    test('Real Model Test Example: [657,142,142,311,172,0,...(23 zeros)...,456] -> [657,142,311,172,456]', () {
      final raw = [
        657, 142, 142, 311, 172,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0,
        456
      ];

      expect(raw.length, 29);

      final res = IsharaCtcDecoder.decodeRawArgmax(raw);
      expect(res.decodedIds, [657, 142, 311, 172, 456]);
      expect(res.rawTimesteps, 29);
      expect(res.blankTimesteps, 23);
      expect(res.nonBlankTimesteps, 6);
      expect(res.collapsedDuplicateCount, 1);
      expect(res.decodedLength, 5);

      // Check positions
      expect(res.positions.length, 5);
      expect(res.positions[0].classId, 657);
      expect(res.positions[0].timestep, 0);
      expect(res.positions[1].classId, 142);
      expect(res.positions[1].timestep, 1);
      expect(res.positions[2].classId, 311);
      expect(res.positions[2].timestep, 3);
      expect(res.positions[3].classId, 172);
      expect(res.positions[3].timestep, 4);
      expect(res.positions[4].classId, 456);
      expect(res.positions[4].timestep, 28);
    });

    test('Report formatting matches Section 14 template exactly', () {
      final raw = [
        657, 142, 142, 311, 172,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0,
        456
      ];

      final res = IsharaCtcDecoder.decodeRawArgmax(raw);
      final report = res.toReportText();

      expect(report.contains('ISHARA CTC DECODER REPORT'), isTrue);
      expect(report.contains('Model Output Shape:\n[1,29,684]'), isTrue);
      expect(report.contains('Blank ID:\n0'), isTrue);
      expect(report.contains('Raw Timesteps:\n29'), isTrue);
      expect(report.contains('Blank Timesteps:\n23'), isTrue);
      expect(report.contains('Non-Blank Timesteps:\n6'), isTrue);
      expect(report.contains('Collapsed Duplicates:\n1'), isTrue);
      expect(report.contains('Decoded Length:\n5'), isTrue);
      expect(report.contains('Decoded IDs:\n\n[657,142,311,172,456]'), isTrue);
      expect(report.contains('657:\nt=0'), isTrue);
      expect(report.contains('142:\nt=1'), isTrue);
      expect(report.contains('311:\nt=3'), isTrue);
      expect(report.contains('172:\nt=4'), isTrue);
      expect(report.contains('456:\nt=28'), isTrue);
      expect(report.contains('Output Shape:\nPASS'), isTrue);
      expect(report.contains('IDs Range:\nPASS'), isTrue);
      expect(report.contains('Blank Removal:\nPASS'), isTrue);
      expect(report.contains('Duplicate Collapse:\nPASS'), isTrue);
      expect(report.contains('Unit Tests:\nPASS'), isTrue);
      expect(report.contains('CTC DECODER:\nPASS'), isTrue);
      expect(report.contains('Vocabulary:\nNOT USED'), isTrue);
      expect(report.contains('Translation:\nNOT USED'), isTrue);
    });

    test('Logits 2D decoding handles argmax, nan and inf correctly', () {
      // 29 timesteps, 684 classes
      final logits = List.generate(
        29,
        (t) => List<double>.filled(684, -10.0),
      );

      // Set argmax classes
      logits[0][657] = 5.0;
      logits[1][142] = 8.0;
      logits[2][142] = 7.5;
      logits[3][311] = 9.0;
      logits[4][172] = 6.2;
      // timesteps 5..27 are all default max at index 0
      for (int t = 5; t <= 27; t++) {
        logits[t][0] = 4.0;
      }
      logits[28][456] = 8.8;

      final res = IsharaCtcDecoder.decodeLogits(logits);
      expect(res.isSuccess, isTrue);
      expect(res.decodedIds, [657, 142, 311, 172, 456]);
      expect(res.blankTimesteps, 23);
      expect(res.collapsedDuplicateCount, 1);
    });

    test('Invalid shape produces CTC_OUTPUT_SHAPE_ERROR', () {
      // 20 timesteps instead of 29
      final invalidLogits = List.generate(
        20,
        (t) => List<double>.filled(684, 0.0),
      );

      final res = IsharaCtcDecoder.decodeLogits(invalidLogits);
      expect(res.isSuccess, isFalse);
      expect(res.errorCode, 'CTC_OUTPUT_SHAPE_ERROR');
    });

    test('Class ID out of range produces CTC_CLASS_ID_OUT_OF_RANGE', () {
      final invalidIds = [0, 5, 700]; // 700 >= 684
      final res = IsharaCtcDecoder.decodeRawArgmax(invalidIds);
      expect(res.isSuccess, isFalse);
      expect(res.errorCode, 'CTC_CLASS_ID_OUT_OF_RANGE');
    });
  });
}
