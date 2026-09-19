import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/models/real_inference_result.dart';

void main() {
  group('Real Sequence Inference Data Models & Comparison Tests', () {
    test('SingleRealInferenceResult correctly records raw argmax with blanks and duplicates preserved', () {
      final now = DateTime(2026, 9, 19, 19, 50, 0);

      // 29 timesteps with blanks (0) and consecutive duplicates (e.g. 53, 53, 53)
      final rawArgmax = [
        0, 0, 0, 53, 53, 53, 0, 122, 122, 0,
        0, 317, 317, 317, 0, 0, 53, 53, 0, 0,
        0, 0, 122, 122, 0, 0, 0, 0, 0
      ];

      expect(rawArgmax.length, 29);

      final uniqueClasses = rawArgmax.toSet().toList()..sort();
      final blankCount = rawArgmax.where((id) => id == 0).length;

      expect(uniqueClasses, [0, 53, 122, 317]);
      expect(blankCount, 19);

      final result = SingleRealInferenceResult(
        testLabel: 'TEST A',
        capturedAt: now,
        isSuccess: true,
        inferenceTimeMs: 412,
        bufferCount: 128,
        inputShape: const [1, 128, 86, 2],
        inputNanCount: 0,
        inputInfCount: 0,
        isChronological: true,
        oldestFrameSequenceId: 100,
        newestFrameSequenceId: 227,
        rawKeypointCoveragePct: 96.76,
        imputationPct: 3.24,
        rightHandCoveragePct: 94.50,
        leftHandCoveragePct: 92.10,
        lipsCoveragePct: 99.80,
        bodyCoveragePct: 98.40,
        outputShape: const [1, 29, 684],
        outputNanCount: 0,
        outputInfCount: 0,
        outputMin: -15.42,
        outputMax: 9.87,
        outputMean: -0.32,
        outputStdDev: 1.45,
        rawArgmax: rawArgmax,
        uniqueClasses: uniqueClasses,
        blankTop1Count: blankCount,
        flatOutput: Float32List(29 * 684),
      );

      expect(result.isSuccess, true);
      expect(result.rawArgmax[0], 0); // blank preserved
      expect(result.rawArgmax[3], 53);
      expect(result.rawArgmax[4], 53); // duplicate preserved
      expect(result.rawArgmax.length, 29);
      expect(result.uniqueClasses, [0, 53, 122, 317]);
      expect(result.blankTop1Count, 19);
    });

    test('RealInferenceComparisonResult compares A vs B correctly when motions differ', () {
      final now = DateTime(2026, 9, 19, 19, 50, 0);

      final rawArgmaxA = List<int>.filled(29, 0);
      rawArgmaxA[5] = 53;
      rawArgmaxA[6] = 53;

      final rawArgmaxB = List<int>.filled(29, 0);
      rawArgmaxB[10] = 122;
      rawArgmaxB[11] = 122;
      rawArgmaxB[12] = 122;

      final flatA = Float32List(29 * 684);
      final flatB = Float32List(29 * 684);

      // Put different logits at certain positions
      flatA[5 * 684 + 53] = 8.5;
      flatB[10 * 684 + 122] = 9.2;

      final resA = SingleRealInferenceResult(
        testLabel: 'TEST A',
        capturedAt: now,
        isSuccess: true,
        inferenceTimeMs: 410,
        bufferCount: 128,
        inputShape: const [1, 128, 86, 2],
        inputNanCount: 0,
        inputInfCount: 0,
        isChronological: true,
        oldestFrameSequenceId: 100,
        newestFrameSequenceId: 227,
        rawKeypointCoveragePct: 96.5,
        imputationPct: 3.5,
        rightHandCoveragePct: 95.0,
        leftHandCoveragePct: 90.0,
        lipsCoveragePct: 100.0,
        bodyCoveragePct: 99.0,
        outputShape: const [1, 29, 684],
        outputNanCount: 0,
        outputInfCount: 0,
        outputMin: -12.0,
        outputMax: 8.5,
        outputMean: -0.2,
        outputStdDev: 1.2,
        rawArgmax: rawArgmaxA,
        uniqueClasses: [0, 53],
        blankTop1Count: 27,
        flatOutput: flatA,
      );

      final resB = SingleRealInferenceResult(
        testLabel: 'TEST B',
        capturedAt: now.add(const Duration(seconds: 10)),
        isSuccess: true,
        inferenceTimeMs: 415,
        bufferCount: 128,
        inputShape: const [1, 128, 86, 2],
        inputNanCount: 0,
        inputInfCount: 0,
        isChronological: true,
        oldestFrameSequenceId: 250,
        newestFrameSequenceId: 377,
        rawKeypointCoveragePct: 97.0,
        imputationPct: 3.0,
        rightHandCoveragePct: 96.0,
        leftHandCoveragePct: 92.0,
        lipsCoveragePct: 100.0,
        bodyCoveragePct: 99.0,
        outputShape: const [1, 29, 684],
        outputNanCount: 0,
        outputInfCount: 0,
        outputMin: -11.5,
        outputMax: 9.2,
        outputMean: -0.15,
        outputStdDev: 1.3,
        rawArgmax: rawArgmaxB,
        uniqueClasses: [0, 122],
        blankTop1Count: 26,
        flatOutput: flatB,
      );

      final comp = RealInferenceComparisonResult.compare(resA, resB);

      // Positions 5, 6 (non-zero in A, 0 in B) and 10, 11, 12 (non-zero in B, 0 in A) changed = 5 positions
      expect(comp.argmaxPositionsChanged, 5);
      expect(comp.maxAbsoluteDifference, closeTo(9.2, 0.001));
      expect(comp.outputsIdentical, false);
      expect(comp.modelRespondsToRealMotion, true);
    });

    test('RealInferenceComparisonResult detects identical outputs', () {
      final now = DateTime(2026, 9, 19, 19, 50, 0);
      final rawArgmax = List<int>.filled(29, 0);
      final flat = Float32List(29 * 684);

      final resA = SingleRealInferenceResult(
        testLabel: 'TEST A',
        capturedAt: now,
        isSuccess: true,
        inferenceTimeMs: 400,
        bufferCount: 128,
        inputShape: const [1, 128, 86, 2],
        inputNanCount: 0,
        inputInfCount: 0,
        isChronological: true,
        oldestFrameSequenceId: 1,
        newestFrameSequenceId: 128,
        rawKeypointCoveragePct: 95.0,
        imputationPct: 5.0,
        rightHandCoveragePct: 90.0,
        leftHandCoveragePct: 90.0,
        lipsCoveragePct: 95.0,
        bodyCoveragePct: 95.0,
        outputShape: const [1, 29, 684],
        outputNanCount: 0,
        outputInfCount: 0,
        outputMin: -10.0,
        outputMax: 5.0,
        outputMean: 0.0,
        outputStdDev: 1.0,
        rawArgmax: rawArgmax,
        uniqueClasses: [0],
        blankTop1Count: 29,
        flatOutput: flat,
      );

      final resB = SingleRealInferenceResult(
        testLabel: 'TEST B',
        capturedAt: now.add(const Duration(seconds: 5)),
        isSuccess: true,
        inferenceTimeMs: 400,
        bufferCount: 128,
        inputShape: const [1, 128, 86, 2],
        inputNanCount: 0,
        inputInfCount: 0,
        isChronological: true,
        oldestFrameSequenceId: 129,
        newestFrameSequenceId: 256,
        rawKeypointCoveragePct: 95.0,
        imputationPct: 5.0,
        rightHandCoveragePct: 90.0,
        leftHandCoveragePct: 90.0,
        lipsCoveragePct: 95.0,
        bodyCoveragePct: 95.0,
        outputShape: const [1, 29, 684],
        outputNanCount: 0,
        outputInfCount: 0,
        outputMin: -10.0,
        outputMax: 5.0,
        outputMean: 0.0,
        outputStdDev: 1.0,
        rawArgmax: rawArgmax,
        uniqueClasses: [0],
        blankTop1Count: 29,
        flatOutput: flat,
      );

      final comp = RealInferenceComparisonResult.compare(resA, resB);

      expect(comp.argmaxPositionsChanged, 0);
      expect(comp.maxAbsoluteDifference, 0.0);
      expect(comp.outputsIdentical, true);
      expect(comp.modelRespondsToRealMotion, false);
    });

    test('toReportText generates report strictly matching section 19 template', () {
      final now = DateTime(2026, 9, 19, 19, 50, 0);

      final rawArgmaxA = List<int>.filled(29, 0);
      rawArgmaxA[3] = 53;
      rawArgmaxA[4] = 53;

      final rawArgmaxB = List<int>.filled(29, 0);
      rawArgmaxB[8] = 122;
      rawArgmaxB[9] = 122;

      final flatA = Float32List(29 * 684);
      final flatB = Float32List(29 * 684);
      flatA[3 * 684 + 53] = 7.5;
      flatB[8 * 684 + 122] = 8.8;

      final testA = SingleRealInferenceResult(
        testLabel: 'TEST A',
        capturedAt: now,
        isSuccess: true,
        inferenceTimeMs: 412,
        bufferCount: 128,
        inputShape: const [1, 128, 86, 2],
        inputNanCount: 0,
        inputInfCount: 0,
        isChronological: true,
        oldestFrameSequenceId: 100,
        newestFrameSequenceId: 227,
        rawKeypointCoveragePct: 96.76,
        imputationPct: 3.24,
        rightHandCoveragePct: 94.50,
        leftHandCoveragePct: 92.10,
        lipsCoveragePct: 99.80,
        bodyCoveragePct: 98.40,
        outputShape: const [1, 29, 684],
        outputNanCount: 0,
        outputInfCount: 0,
        outputMin: -15.4200,
        outputMax: 9.8700,
        outputMean: -0.3200,
        outputStdDev: 1.4500,
        rawArgmax: rawArgmaxA,
        uniqueClasses: [0, 53],
        blankTop1Count: 27,
        flatOutput: flatA,
      );

      final testB = SingleRealInferenceResult(
        testLabel: 'TEST B',
        capturedAt: now.add(const Duration(seconds: 15)),
        isSuccess: true,
        inferenceTimeMs: 408,
        bufferCount: 128,
        inputShape: const [1, 128, 86, 2],
        inputNanCount: 0,
        inputInfCount: 0,
        isChronological: true,
        oldestFrameSequenceId: 240,
        newestFrameSequenceId: 367,
        rawKeypointCoveragePct: 97.10,
        imputationPct: 2.90,
        rightHandCoveragePct: 95.00,
        leftHandCoveragePct: 93.50,
        lipsCoveragePct: 100.00,
        bodyCoveragePct: 99.00,
        outputShape: const [1, 29, 684],
        outputNanCount: 0,
        outputInfCount: 0,
        outputMin: -14.1000,
        outputMax: 8.8000,
        outputMean: -0.2800,
        outputStdDev: 1.3800,
        rawArgmax: rawArgmaxB,
        uniqueClasses: [0, 122],
        blankTop1Count: 27,
        flatOutput: flatB,
      );

      final comparison = RealInferenceComparisonResult.compare(testA, testB);

      final session = RealInferenceSession(
        testA: testA,
        testB: testB,
        comparison: comparison,
        framesSinceTestA: 128,
      );

      final report = session.toReportText();

      // Check section headers
      expect(report.contains('================================\nISHARA REAL INFERENCE REPORT\n================================'), true);
      expect(report.contains('Model:\nishara_model.tflite'), true);
      expect(report.contains('Model Size:\n107.55 MB'), true);
      expect(report.contains('Interpreter:\nREADY'), true);

      // Check REAL INPUT section
      expect(report.contains('REAL INPUT\n\nBuffer:\n128/128\n\nInput Shape:\n[1,128,86,2]\n\nNaN:\n0\n\nInfinity:\n0\n\nChronological:\nPASS\n\nSequence Quality:\n96.76 %\n\nImputation:\n3.24 %\n\nRH Coverage:\n94.50 %\n\nLH Coverage:\n92.10 %\n\nLips Coverage:\n99.80 %\n\nBody Coverage:\n98.40 %'), true);

      // Check TEST A section
      expect(report.contains('TEST A\n\nInference:\nPASS\n\nInference Time:\n412 ms\n\nOutput Shape:\n[1,29,684]\n\nOutput NaN:\n0\n\nOutput Infinity:\n0\n\nOutput Min:\n-15.4200\n\nOutput Max:\n9.8700'), true);
      expect(report.contains('Blank Top-1:\n27 / 29'), true);

      // Check TEST B section
      expect(report.contains('TEST B\n\nInference:\nPASS\n\nInference Time:\n408 ms\n\nOutput Shape:\n[1,29,684]'), true);

      // Check A vs B section
      expect(report.contains('A vs B\n\nArgmax Positions Changed:\n4 / 29'), true);
      expect(report.contains('Outputs Identical:\nNO'), true);
      expect(report.contains('MODEL RESPONDS TO REAL MOTION:\nYES'), true);

      // Check FINAL RESULT
      expect(report.contains('FINAL RESULT\n\nREAL PIPELINE:\nPASS\n\nFirst Failure Point:\nNone\n\nErrors:\nNone'), true);
    });

    test('Failure conditions produce exact error codes without crash', () {
      final now = DateTime(2026, 9, 19, 19, 50, 0);

      final shapeFail = SingleRealInferenceResult.failure(
        testLabel: 'TEST A',
        capturedAt: now,
        errorCode: 'E_REAL_INPUT_SHAPE',
        errorMessage: 'Invalid real input shape: [1, 64, 86, 2] (Expected [1,128,86,2])',
      );
      expect(shapeFail.isSuccess, false);
      expect(shapeFail.errorCode, 'E_REAL_INPUT_SHAPE');

      final nanFail = SingleRealInferenceResult.failure(
        testLabel: 'TEST A',
        capturedAt: now,
        errorCode: 'E_REAL_INPUT_NAN',
        errorMessage: 'Real input contains 3 NaN values',
      );
      expect(nanFail.isSuccess, false);
      expect(nanFail.errorCode, 'E_REAL_INPUT_NAN');

      final infFail = SingleRealInferenceResult.failure(
        testLabel: 'TEST A',
        capturedAt: now,
        errorCode: 'E_REAL_INPUT_INF',
        errorMessage: 'Real input contains 1 Infinity values',
      );
      expect(infFail.isSuccess, false);
      expect(infFail.errorCode, 'E_REAL_INPUT_INF');

      final bufferFail = SingleRealInferenceResult.failure(
        testLabel: 'TEST A',
        capturedAt: now,
        bufferCount: 75,
        errorCode: 'E_BUFFER_NOT_READY',
        errorMessage: 'Buffer not full: 75/128 frames',
      );
      expect(bufferFail.isSuccess, false);
      expect(bufferFail.errorCode, 'E_BUFFER_NOT_READY');
    });
  });
}
