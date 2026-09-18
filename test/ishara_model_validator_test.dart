import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/ml/model/ishara_model_validator.dart';

void main() {
  group('IsharaModelValidator Tests', () {
    test('Detects Git LFS pointer and rejects it with E_MODEL_LFS_POINTER', () {
      final lfsPointer = Uint8List.fromList(
        'version https://git-lfs.github.com/spec/v1\noid sha256:abc123\nsize 112770792\n'.codeUnits,
      );

      final result = IsharaModelValidator.validateModelBytes(lfsPointer);
      expect(result.isValid, false);
      expect(result.errorCode, 'E_MODEL_LFS_POINTER');
      expect(result.errorMessage, contains('GIT_LFS_POINTER_NOT_MODEL'));
    });

    test('Rejects file smaller than 100 KB with E_MODEL_FILE_TOO_SMALL', () {
      final smallBytes = Uint8List(500); // 500 bytes

      final result = IsharaModelValidator.validateModelBytes(smallBytes);
      expect(result.isValid, false);
      expect(result.errorCode, 'E_MODEL_FILE_TOO_SMALL');
      expect(result.errorMessage, contains('INVALID_MODEL_ASSET'));
    });

    test('Validates tensor shapes strictly using listEquals', () {
      // Exact match
      final matchError = IsharaModelValidator.validateTensorShapes(
        actualInputShape: [1, 128, 86, 2],
        actualOutputShape: [1, 29, 684],
      );
      expect(matchError, isNull);

      // Input shape mismatch
      final inError = IsharaModelValidator.validateTensorShapes(
        actualInputShape: [1, 64, 86, 2],
        actualOutputShape: [1, 29, 684],
      );
      expect(inError, contains('E_INPUT_SHAPE'));

      // Output shape mismatch
      final outError = IsharaModelValidator.validateTensorShapes(
        actualInputShape: [1, 128, 86, 2],
        actualOutputShape: [1, 29, 500],
      );
      expect(outError, contains('E_OUTPUT_SHAPE'));
    });

    test('Validates output tensor [1, 29, 684] and computes argmax correctly', () {
      final mockOutput = List.generate(
        1,
        (_) => List.generate(
          29,
          (t) => List<double>.generate(684, (c) => c == t * 10 ? 10.0 : 0.1),
        ),
      );

      final report = IsharaModelValidator.validateOutputTensor(mockOutput);
      expect(report.isValid, true);
      expect(report.nanCount, 0);
      expect(report.infCount, 0);
      expect(report.argmaxIds.length, 29);
      expect(report.argmaxIds[0], 0);
      expect(report.argmaxIds[1], 10);
      expect(report.argmaxIds[2], 20);

      final topLogits = IsharaModelValidator.extractTopLogits(mockOutput, sampleInterval: 10);
      expect(topLogits.length, 3); // t=0, t=10, t=20
      expect(topLogits[0].topClassId, 0);
      expect(topLogits[0].topScore, 10.0);
    });

    test('Detects NaN in output tensor and flags E_OUTPUT_NAN', () {
      final nanOutput = List.generate(
        1,
        (_) => List.generate(
          29,
          (t) => List<double>.generate(684, (c) => (t == 5 && c == 3) ? double.nan : 0.5),
        ),
      );

      final report = IsharaModelValidator.validateOutputTensor(nanOutput);
      expect(report.isValid, false);
      expect(report.errorCode, 'E_OUTPUT_NAN');
      expect(report.nanCount, 1);
    });

    test('Detects output change between different sequences (isResponsive)', () {
      final seqA = List.generate(29, (i) => i);
      final seqB = List.generate(29, (i) => i == 10 ? 99 : i);
      final seqSame = List.generate(29, (i) => i);

      expect(IsharaModelValidator.hasOutputChanged(seqA, seqB), true);
      expect(IsharaModelValidator.hasOutputChanged(seqA, seqSame), false);
    });
  });
}
