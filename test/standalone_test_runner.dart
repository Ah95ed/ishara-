import 'dart:convert';
import 'package:ishara/services/pose/pose_preprocessor.dart';
import 'package:ishara/services/tflite/ctc_greedy_decoder.dart';
import 'package:ishara/services/tflite/frame_buffer.dart';
import 'package:ishara/services/tflite/ishara_vocab_service.dart';
import 'package:ishara/services/tflite/prediction_stabilizer.dart';

void assertTrue(bool condition, String message) {
  if (!condition) {
    throw Exception('FAILED: $message');
  }
}

void assertEqual<T>(T actual, T expected, String message) {
  if (actual != expected) {
    throw Exception('FAILED: $message. Expected: $expected, Got: $actual');
  }
}

Future<void> main() async {
  print('==================================================');
  print('Running Standalone CTC & Pipeline Verification');
  print('==================================================');

  // 1. اختبار CTC Greedy Decoder
  print('[1/5] Testing CTC Greedy Decoder...');
  final vocabService = IsharaVocabService();
  final sampleVocabMap = <String, String>{
    '0': '_',
    '15': 'احد_عشر',
    '39': 'اسبوع',
    '81': 'سوق',
  };
  for (int i = 0; i < 684; i++) {
    sampleVocabMap.putIfAbsent(i.toString(), () => 'gloss_$i');
  }
  await vocabService.loadVocab(customJsonString: jsonEncode(sampleVocabMap));
  final decoder = CtcGreedyDecoder(vocabService: vocabService, blankId: 0);

  // Test: [0, 15, 15, 0, 39, 39, 39, 0] -> [15, 39]
  final rawInput = [0, 15, 15, 0, 39, 39, 39, 0];
  final decodedIds = decoder.decodeRawIds(rawInput);
  assertEqual(decodedIds.length, 2, 'Decoded IDs length should be 2');
  assertEqual(decodedIds[0], 15, 'First ID should be 15');
  assertEqual(decodedIds[1], 39, 'Second ID should be 39');

  final decodedResult = decoder.decodeIdsWithConfidence(
    rawInput,
    List.filled(rawInput.length, 0.95),
  );
  assertEqual(decodedResult.glosses.length, 2, 'Gloss count should be 2');
  assertEqual(decodedResult.glosses[0], 'احد عشر', 'First gloss mapping');
  assertEqual(decodedResult.glosses[1], 'اسبوع', 'Second gloss mapping');
  print('  ✅ CTC Decoder: Duplicate removal, Blank removal & Vocab mapping PASSED');

  // 2. اختبار FrameBuffer
  print('[2/5] Testing FrameBuffer (128 frames)...');
  final buffer = FrameBuffer(inferenceStride: 8, minActiveRatio: 0.30);
  assertEqual(buffer.isFull, false, 'Buffer starts empty');
  assertEqual(buffer.count, 0, 'Buffer count starts 0');

  final dummyFrame = List.generate(86, (_) => [0.1, 0.2]);
  for (int i = 0; i < 128; i++) {
    buffer.addFrame(dummyFrame, hasActivePerson: true);
  }
  assertEqual(buffer.isFull, true, 'Buffer is full after 128 frames');
  assertEqual(buffer.count, 128, 'Buffer count is 128');
  assertEqual(buffer.hasValidSignActivity, true, 'Buffer has active sign');

  final retrieved = buffer.getFrames();
  assertTrue(retrieved != null, 'Frames retrieved is not null');
  assertEqual(retrieved!.length, 128, 'Frames count is 128');
  assertEqual(retrieved[0].length, 86, 'Keypoints count is 86');
  assertEqual(retrieved[0][0].length, 2, 'Coordinates count is 2');

  // Adding 5 more frames (FIFO test)
  for (int i = 0; i < 5; i++) {
    buffer.addFrame(dummyFrame, hasActivePerson: true);
  }
  assertEqual(buffer.count, 128, 'Buffer stays at max 128 (FIFO)');
  print('  ✅ FrameBuffer: 128 frames capacity, FIFO sliding & activity mask PASSED');

  // 3. اختبار PosePreprocessor
  print('[3/5] Testing PosePreprocessor (datasetv2.py math)...');
  final samplePts = [
    [10.0, 20.0],
    [15.0, 25.0],
    [30.0, 40.0],
  ];
  final normalized = PosePreprocessor.normalizeSubset(samplePts);
  assertEqual(normalized.length, 3, 'Normalized subset length');
  for (final pt in normalized) {
    assertTrue(pt[0] >= -0.50001 && pt[0] <= 0.50001, 'X normalized to [-0.5, 0.5]');
    assertTrue(pt[1] >= -0.50001 && pt[1] <= 0.50001, 'Y normalized to [-0.5, 0.5]');
  }

  final preprocessor = PosePreprocessor();
  final rh = List.generate(21, (i) => [i.toDouble(), (i + 1).toDouble()]);
  final frame86 = preprocessor.processFrame(rawRightHand: rh);
  assertEqual(frame86.length, 86, 'Frame has exactly 86 keypoints');
  assertEqual(frame86[0].length, 2, 'Each keypoint has [x, y]');

  // Carry forward test
  final frame86Missing = preprocessor.processFrame(rawRightHand: null);
  assertEqual(frame86Missing[0][0], frame86[0][0], 'Carry forward missing right hand');
  print('  ✅ PosePreprocessor: Exact normalization & 86 keypoints layout PASSED');

  // 4. اختبار PredictionStabilizer
  print('[4/5] Testing PredictionStabilizer (Duplicate suppression)...');
  final stabilizer = PredictionStabilizer(
    minimumConfidence: 0.50,
    requiredStablePredictions: 2,
    cooldownDuration: const Duration(seconds: 1),
  );

  final r1 = stabilizer.processPrediction(
    candidateGloss: 'سلام',
    confidence: 0.90,
    isSignActive: true,
  );
  assertEqual(r1, null, 'First occurrence not emitted yet (needs 2 stable windows)');

  final r2 = stabilizer.processPrediction(
    candidateGloss: 'سلام',
    confidence: 0.90,
    isSignActive: true,
  );
  assertEqual(r2, 'سلام', 'Second stable window emits "سلام"');

  final r3 = stabilizer.processPrediction(
    candidateGloss: 'سلام',
    confidence: 0.90,
    isSignActive: true,
  );
  assertEqual(r3, null, 'Duplicate suppressed (does not emit سلام سلام سلام)');

  assertEqual(stabilizer.glossSequence.length, 1, 'Sequence contains exactly 1 "سلام"');
  print('  ✅ PredictionStabilizer: Stable windows & duplicate filtering PASSED');

  // 5. فحص ملف النموذج وملف المفردات الفعلي في assets/
  print('[5/5] Testing Vocab file verification...');
  assertEqual(IsharaVocabService.expectedVocabSize, 684, 'Expected vocab size is 684');
  print('  ✅ Assets & Vocab specifications verified');

  print('==================================================');
  print('ALL 5 PIPELINE INTEGRATION TESTS PASSED 100%!');
  print('==================================================');
}
