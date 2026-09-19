import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/models/model_smoke_test_result.dart';

void main() {
  group('Model Smoke Test Result & Report Format Tests', () {
    test('Successful smoke test report format matches exact specification', () {
      final now = DateTime(2026, 9, 19, 13, 0, 0);
      final result = ModelSmokeTestResult(
        capturedAt: now,
        modelPath: 'assets/models/ishara_model.tflite',
        fileExists: true,
        sizeBytes: 112770792,
        sizeMb: 107.55,
        isLfsPointer: false,
        fileValidationPass: true,
        interpreterReady: true,
        interpreterLoadTimeMs: 45,
        actualInputShape: const [1, 128, 86, 2],
        actualInputType: 'float32',
        inputValidationPass: true,
        actualOutputShape: const [1, 29, 684],
        actualOutputType: 'float32',
        outputValidationPass: true,
        zeroInferencePass: true,
        zeroInferenceTimeMs: 38,
        nanCount: 0,
        infCount: 0,
        outputMin: -12.45,
        outputMax: 8.92,
        firstOutputValues: const [-2.1, 0.45, 1.2, -0.05, 3.12],
        secondInferencePass: true,
        outputChanged: true,
        maxAbsoluteDifference: 4.87,
        isOverallPass: true,
        firstFailurePoint: 'NONE',
        errorMessage: 'None',
      );

      final report = result.toReportText();

      // Check required sections and exact labels
      expect(report.contains('ISHARA MODEL SMOKE TEST REPORT'), true);
      expect(report.contains('Model Path:\nassets/models/ishara_model.tflite'), true);
      expect(report.contains('MODEL FILE\n\nExists:\nYES\n\nSize Bytes:\n112770792\n\nSize MB:\n107.55 MB\n\nLFS Pointer:\nNO\n\nFile Validation:\nPASS'), true);
      expect(report.contains('INTERPRETER\n\nStatus:\nREADY\n\nLoad Time:\n45 ms\n\nError:\nNone'), true);
      expect(report.contains('INPUT TENSOR\n\nActual Shape:\n[1,128,86,2]\n\nExpected Shape:\n[1,128,86,2]\n\nActual Type:\nfloat32\n\nExpected Type:\nfloat32\n\nValidation:\nPASS'), true);
      expect(report.contains('OUTPUT TENSOR\n\nActual Shape:\n[1,29,684]\n\nExpected Shape:\n[1,29,684]\n\nActual Type:\nfloat32\n\nExpected Type:\nfloat32\n\nValidation:\nPASS'), true);
      expect(report.contains('ZERO INPUT TEST\n\nInference:\nPASS\n\nInference Time:\n38 ms\n\nNaN:\n0\n\nInfinity:\n0\n\nOutput Min:\n-12.4500\n\nOutput Max:\n8.9200'), true);
      expect(report.contains('SECOND INPUT TEST\n\nInference:\nPASS\n\nOutput Changed:\nYES\n\nMax Absolute Difference:\n4.8700'), true);
      expect(report.contains('FINAL RESULT\n\nPASS\n\nFirst Failure Point:\nNONE\n\nError Message:\nNone'), true);
    });

    test('Early failure at Interpreter creation produces full report with error details', () {
      final now = DateTime(2026, 9, 19, 13, 0, 0);
      final result = ModelSmokeTestResult(
        capturedAt: now,
        modelPath: 'assets/models/ishara_model.tflite',
        fileExists: true,
        sizeBytes: 112770792,
        sizeMb: 107.55,
        isLfsPointer: false,
        fileValidationPass: true,
        interpreterReady: false,
        interpreterLoadTimeMs: 12,
        interpreterError: 'ArgumentError: Invalid binary flatbuffer',
        inputValidationPass: false,
        outputValidationPass: false,
        zeroInferencePass: false,
        zeroInferenceTimeMs: 0,
        nanCount: 0,
        infCount: 0,
        secondInferencePass: false,
        outputChanged: false,
        maxAbsoluteDifference: 0.0,
        isOverallPass: false,
        firstFailurePoint: 'INTERPRETER',
        errorMessage: 'Interpreter.fromBuffer failed: ArgumentError: Invalid binary flatbuffer',
      );

      final report = result.toReportText();

      expect(report.contains('File Validation:\nPASS'), true);
      expect(report.contains('Status:\nFAIL'), true);
      expect(report.contains('Error:\nArgumentError: Invalid binary flatbuffer'), true);
      expect(report.contains('FINAL RESULT\n\nFAIL'), true);
      expect(report.contains('First Failure Point:\nINTERPRETER'), true);
      expect(report.contains('Error Message:\nInterpreter.fromBuffer failed: ArgumentError: Invalid binary flatbuffer'), true);
    });
  });
}
