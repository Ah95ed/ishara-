import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/services/pose/pose_preprocessor.dart';
import 'package:ishara/services/tflite/ctc_greedy_decoder.dart';
import 'package:ishara/services/tflite/frame_buffer.dart';
import 'package:ishara/services/tflite/ishara_vocab_service.dart';
import 'package:ishara/services/tflite/prediction_stabilizer.dart';

void main() {
  group('1. CTC Greedy Decoder Tests', () {
    late IsharaVocabService vocabService;
    late CtcGreedyDecoder decoder;

    setUp(() async {
      vocabService = IsharaVocabService();
      // محاكاة قاموس مبسط للاختبار
      final sampleVocabMap = <String, String>{
        '0': '_',
        '15': 'احد_عشر',
        '39': 'اسبوع',
        '81': 'سوق',
      };
      // إكمال الـ 684 فئة لتمرير الفحص الصارم
      for (int i = 0; i < 684; i++) {
        final k = i.toString();
        sampleVocabMap.putIfAbsent(k, () => 'gloss_$i');
      }
      await vocabService.loadVocab(customJsonString: jsonEncode(sampleVocabMap));
      decoder = CtcGreedyDecoder(vocabService: vocabService, blankId: 0);
    });

    test('CTC duplicate removal and blank removal: [0, 15, 15, 0, 39, 39, 39, 0] -> [15, 39]', () {
      final input = [0, 15, 15, 0, 39, 39, 39, 0];
      final expected = [15, 39];

      final result = decoder.decodeRawIds(input);
      expect(result, equals(expected));
    });

    test('Vocabulary mapping from IDs to Arabic glosses', () {
      final input = [0, 15, 15, 0, 39, 39, 39, 0];
      final confs = List.filled(input.length, 0.95);

      final decoded = decoder.decodeIdsWithConfidence(input, confs);
      expect(decoded.glossIds, equals([15, 39]));
      expect(decoded.glosses, equals(['احد عشر', 'اسبوع']));
      expect(decoded.averageConfidence, closeTo(0.95, 0.001));
    });

    test('Empty input returns empty result', () {
      final result = decoder.decodeRawIds([]);
      expect(result, isEmpty);
    });

    test('Only blanks input returns empty result', () {
      final result = decoder.decodeRawIds([0, 0, 0, 0]);
      expect(result, isEmpty);
    });
  });

  group('2. FrameBuffer Tests', () {
    test('128 frame buffer capacity, fullness, and FIFO sliding', () {
      final buffer = FrameBuffer(inferenceStride: 8);
      expect(buffer.isFull, isFalse);
      expect(buffer.count, equals(0));

      // إنشاء إطار وهمي [86, 2]
      final dummyFrame = List.generate(86, (_) => [0.1, 0.2]);

      // إضافة 100 إطار
      for (int i = 0; i < 100; i++) {
        buffer.addFrame(dummyFrame, hasActivePerson: true);
      }
      expect(buffer.isFull, isFalse);
      expect(buffer.count, equals(100));
      expect(buffer.getFrames(), isNull);

      // إضافة 28 إطار لتكتمل الـ 128
      for (int i = 0; i < 28; i++) {
        buffer.addFrame(dummyFrame, hasActivePerson: true);
      }
      expect(buffer.isFull, isTrue);
      expect(buffer.count, equals(128));

      final frames = buffer.getFrames();
      expect(frames, isNotNull);
      expect(frames!.length, equals(128));
      expect(frames[0].length, equals(86));
      expect(frames[0][0].length, equals(2));

      // إضافة 10 إطارات إضافية (اختبار FIFO - يظل الحجم 128)
      for (int i = 0; i < 10; i++) {
        buffer.addFrame(dummyFrame, hasActivePerson: true);
      }
      expect(buffer.count, equals(128));
    });

    test('Activity mask detects presence of sign activity', () {
      final buffer = FrameBuffer(minActiveRatio: 0.30);
      final dummyFrame = List.generate(86, (_) => [0.0, 0.0]);

      // إضافة 128 إطاراً كلها غير نشطة
      for (int i = 0; i < 128; i++) {
        buffer.addFrame(dummyFrame, hasActivePerson: false);
      }
      expect(buffer.hasValidSignActivity, isFalse);

      // إضافة إطارات نشطة
      for (int i = 0; i < 60; i++) {
        buffer.addFrame(dummyFrame, hasActivePerson: true);
      }
      expect(buffer.hasValidSignActivity, isTrue);
    });
  });

  group('3. PosePreprocessor Tests', () {
    test('Normalizes points into [-0.5, 0.5] range matching datasetv2.py', () {
      final sample = [
        [10.0, 20.0],
        [15.0, 25.0],
        [30.0, 40.0],
      ];
      final norm = PosePreprocessor.normalizeSubset(sample);
      expect(norm.length, equals(3));

      for (final p in norm) {
        expect(p[0], greaterThanOrEqualTo(-0.50001));
        expect(p[0], lessThanOrEqualTo(0.50001));
        expect(p[1], greaterThanOrEqualTo(-0.50001));
        expect(p[1], lessThanOrEqualTo(0.50001));
      }
    });

    test('ProcessFrame produces exactly 86 keypoints with [86, 2] shape', () {
      final preprocessor = PosePreprocessor();
      final rh = List.generate(21, (i) => [i.toDouble(), (i + 1).toDouble()]);
      final lh = List.generate(21, (i) => [i.toDouble(), (i + 2).toDouble()]);

      final frame = preprocessor.processFrame(
        rawRightHand: rh,
        rawLeftHand: lh,
      );

      expect(frame.length, equals(86));
      for (final pt in frame) {
        expect(pt.length, equals(2));
      }
    });

    test('Missing landmarks carry-forward from previous frame', () {
      final preprocessor = PosePreprocessor();
      final rh1 = List.generate(21, (i) => [10.0 + i, 20.0 + i]);
      final frame1 = preprocessor.processFrame(rawRightHand: rh1);

      // في الإطار الثاني، نفقد اليد اليمنى
      final frame2 = preprocessor.processFrame(rawRightHand: null);

      // يجب أن تكون نقاط اليد اليمنى في frame2 مطابقة لـ frame1 (carry forward)
      for (int i = 0; i < 21; i++) {
        expect(frame2[i][0], equals(frame1[i][0]));
        expect(frame2[i][1], equals(frame1[i][1]));
      }
    });
  });

  group('4. PredictionStabilizer & Repeated Gloss Filtering Tests', () {
    test('Filters immediate duplicates (سلام سلام سلام -> سلام)', () {
      final stabilizer = PredictionStabilizer(
        minimumConfidence: 0.50,
        requiredStablePredictions: 2,
        cooldownDuration: const Duration(seconds: 1),
      );

      // أول تنبؤ: لا يعتمد لأنه يحتاج 2 نوافذ مستقرة
      final p1 = stabilizer.processPrediction(
        candidateGloss: 'سلام',
        confidence: 0.90,
        isSignActive: true,
      );
      expect(p1, isNull);

      // ثاني تنبؤ مستقر: يعتمد 'سلام'
      final p2 = stabilizer.processPrediction(
        candidateGloss: 'سلام',
        confidence: 0.90,
        isSignActive: true,
      );
      expect(p2, equals('سلام'));

      // ثالث تنبؤ متكرر: لا يعاد كتابته (null)
      final p3 = stabilizer.processPrediction(
        candidateGloss: 'سلام',
        confidence: 0.90,
        isSignActive: true,
      );
      expect(p3, isNull);

      // رابع تنبؤ متكرر: لا يعاد كتابته (null)
      final p4 = stabilizer.processPrediction(
        candidateGloss: 'سلام',
        confidence: 0.90,
        isSignActive: true,
      );
      expect(p4, isNull);

      expect(stabilizer.glossSequence, equals(['سلام']));
    });

    test('Ignores predictions when sign is inactive or confidence below threshold', () {
      final stabilizer = PredictionStabilizer(minimumConfidence: 0.60);

      // ثقة منخفضة
      final p1 = stabilizer.processPrediction(
        candidateGloss: 'شكرا',
        confidence: 0.40,
        isSignActive: true,
      );
      expect(p1, isNull);

      // لا توجد يد / شخص
      final p2 = stabilizer.processPrediction(
        candidateGloss: 'شكرا',
        confidence: 0.95,
        isSignActive: false,
      );
      expect(p2, isNull);
    });

    test('Allows repeating gloss after sign ends and is performed again', () {
      final stabilizer = PredictionStabilizer(
        minimumConfidence: 0.50,
        requiredStablePredictions: 1,
        cooldownDuration: const Duration(milliseconds: 100),
      );

      final p1 = stabilizer.processPrediction(
        candidateGloss: 'شكرا',
        confidence: 0.85,
        isSignActive: true,
      );
      expect(p1, equals('شكرا'));

      // انتهاء الإشارة (إنزال اليدين)
      stabilizer.onSignEnded();

      // إعادة تنفيذ نفس الإشارة بعد التوقف
      final p2 = stabilizer.processPrediction(
        candidateGloss: 'شكرا',
        confidence: 0.85,
        isSignActive: true,
      );
      expect(p2, equals('شكرا'));
      expect(stabilizer.glossSequence, equals(['شكرا', 'شكرا']));
    });
  });
}
