/// نتيجة فحص واختبار نموذج الذكاء الاصطناعي (Model Smoke Test Result)
class ModelSmokeTestResult {
  final DateTime capturedAt;
  final String modelPath;

  // TEST 1 — Model File
  final bool fileExists;
  final int sizeBytes;
  final double sizeMb;
  final bool isLfsPointer;
  final bool fileValidationPass;

  // TEST 2 — Interpreter
  final bool interpreterReady;
  final int interpreterLoadTimeMs;
  final String? interpreterError;

  // TEST 3 — Input Tensor
  final List<int>? actualInputShape;
  final List<int> expectedInputShape;
  final String? actualInputType;
  final String expectedInputType;
  final bool inputValidationPass;

  // TEST 4 — Output Tensor
  final List<int>? actualOutputShape;
  final List<int> expectedOutputShape;
  final String? actualOutputType;
  final String expectedOutputType;
  final bool outputValidationPass;

  // TEST 5 & 6 — Zero Input Test & Output Validation
  final bool zeroInferencePass;
  final int zeroInferenceTimeMs;
  final int nanCount;
  final int infCount;
  final double? outputMin;
  final double? outputMax;
  final List<double> firstOutputValues;

  // TEST 7 — Second Input Test
  final bool secondInferencePass;
  final bool outputChanged;
  final double maxAbsoluteDifference;

  // Final Overall Result
  final bool isOverallPass;
  final String firstFailurePoint;
  final String errorMessage;

  const ModelSmokeTestResult({
    required this.capturedAt,
    required this.modelPath,
    required this.fileExists,
    required this.sizeBytes,
    required this.sizeMb,
    required this.isLfsPointer,
    required this.fileValidationPass,
    required this.interpreterReady,
    required this.interpreterLoadTimeMs,
    this.interpreterError,
    this.actualInputShape,
    this.expectedInputShape = const [1, 128, 86, 2],
    this.actualInputType,
    this.expectedInputType = 'float32',
    required this.inputValidationPass,
    this.actualOutputShape,
    this.expectedOutputShape = const [1, 29, 684],
    this.actualOutputType,
    this.expectedOutputType = 'float32',
    required this.outputValidationPass,
    required this.zeroInferencePass,
    required this.zeroInferenceTimeMs,
    required this.nanCount,
    required this.infCount,
    this.outputMin,
    this.outputMax,
    this.firstOutputValues = const [],
    required this.secondInferencePass,
    required this.outputChanged,
    required this.maxAbsoluteDifference,
    required this.isOverallPass,
    required this.firstFailurePoint,
    required this.errorMessage,
  });

  /// توليد النص المطابق تماماً لمتطلبات التقرير
  String toReportText() {
    final dateStr = capturedAt.toIso8601String().replaceFirst('T', ' ').split('.').first;
    final firstValsFormatted = firstOutputValues
        .map((v) => v.toStringAsFixed(4))
        .join(', ');

    return '''
================================
ISHARA MODEL SMOKE TEST REPORT
================================

Captured At:
$dateStr

Model Path:
$modelPath

--------------------------------

MODEL FILE

Exists:
${fileExists ? 'YES' : 'NO'}

Size Bytes:
$sizeBytes

Size MB:
${sizeMb.toStringAsFixed(2)} MB

LFS Pointer:
${isLfsPointer ? 'YES' : 'NO'}

File Validation:
${fileValidationPass ? 'PASS' : 'FAIL'}

--------------------------------

INTERPRETER

Status:
${interpreterReady ? 'READY' : 'FAIL'}

Load Time:
$interpreterLoadTimeMs ms

Error:
${interpreterError ?? 'None'}

--------------------------------

INPUT TENSOR

Actual Shape:
${actualInputShape != null ? actualInputShape.toString().replaceAll(' ', '') : '--'}

Expected Shape:
${expectedInputShape.toString().replaceAll(' ', '')}

Actual Type:
${actualInputType ?? '--'}

Expected Type:
$expectedInputType

Validation:
${inputValidationPass ? 'PASS' : 'FAIL'}

--------------------------------

OUTPUT TENSOR

Actual Shape:
${actualOutputShape != null ? actualOutputShape.toString().replaceAll(' ', '') : '--'}

Expected Shape:
${expectedOutputShape.toString().replaceAll(' ', '')}

Actual Type:
${actualOutputType ?? '--'}

Expected Type:
$expectedOutputType

Validation:
${outputValidationPass ? 'PASS' : 'FAIL'}

--------------------------------

ZERO INPUT TEST

Inference:
${zeroInferencePass ? 'PASS' : 'FAIL'}

Inference Time:
$zeroInferenceTimeMs ms

NaN:
$nanCount

Infinity:
$infCount

Output Min:
${outputMin != null ? outputMin!.toStringAsFixed(4) : '--'}

Output Max:
${outputMax != null ? outputMax!.toStringAsFixed(4) : '--'}

First Output Values:
[$firstValsFormatted]

--------------------------------

SECOND INPUT TEST

Inference:
${secondInferencePass ? 'PASS' : 'FAIL'}

Output Changed:
${outputChanged ? 'YES' : 'NO'}

Max Absolute Difference:
${maxAbsoluteDifference.toStringAsFixed(4)}

--------------------------------

FINAL RESULT

${isOverallPass ? 'PASS' : 'FAIL'}

First Failure Point:
$firstFailurePoint

Error Message:
$errorMessage

================================
'''.trim();
  }
}
