import 'dart:convert';

/// حالة المرحلة التشخيصية
enum DiagnosticStageStatus {
  pass('PASS', '✅'),
  fail('FAIL', '❌'),
  waiting('WAITING', '⏳'),
  running('RUNNING', '🔄'),
  skipped('SKIPPED', '⏸');

  final String label;
  final String icon;
  const DiagnosticStageStatus(this.label, this.icon);

  String get displayText => '$label $icon';
}

/// رموز الأخطاء الثابتة الصارمة للمطور
class DiagnosticErrorCodes {
  // Model Diagnostic Error Codes (Part A)
  static const String e001ModelAssetNotFound = 'E001_MODEL_ASSET_NOT_FOUND';
  static const String e002ModelAssetEmpty = 'E002_MODEL_ASSET_EMPTY';
  static const String e010InterpreterCreateFailed = 'E010_INTERPRETER_CREATE_FAILED';
  static const String e011TensorShapeMismatch = 'E011_TENSOR_SHAPE_MISMATCH';
  static const String e012StandaloneInferenceFailed = 'E012_STANDALONE_INFERENCE_FAILED';
  static const String e020VocabMissingIds = 'E020_VOCAB_MISSING_IDS';

  // Camera & Person Detection Error Codes (Part B)
  static const String e101PersonDetectorNotCalled = 'E101_PERSON_DETECTOR_NOT_CALLED';
  static const String e102PersonDetectorException = 'E102_PERSON_DETECTOR_EXCEPTION';
  static const String e110ImageConversionFailed = 'E110_IMAGE_CONVERSION_FAILED';

  // Sign Pipeline Error Codes
  static const String e201KeypointCount = 'E201_KEYPOINT_COUNT';
  static const String e301PreprocessNan = 'E301_PREPROCESS_NAN';
  static const String e401BufferNotFilling = 'E401_BUFFER_NOT_FILLING';
  static const String e501RealModelInputInvalid = 'E501_REAL_MODEL_INPUT_INVALID';

  // Legacy compatibility error codes
  static const String e001CameraNoFrames = 'E001_CAMERA_NO_FRAMES';
  static const String e002CameraRotation = 'E002_CAMERA_ROTATION';
  static const String e101PersonNotDetected = 'E101_PERSON_NOT_DETECTED';
  static const String e201NoHand = 'E201_NO_HAND';
  static const String e301KeypointCount = 'E201_KEYPOINT_COUNT';
  static const String e301KeypointCountLegacy = 'E301_KEYPOINT_COUNT';
  static const String e302InvalidKeypointValues = 'E302_INVALID_KEYPOINT_VALUES';
  static const String e303MappingFailure = 'E303_MAPPING_FAILURE';
  static const String e401PreprocessingNan = 'E401_PREPROCESSING_NAN';
  static const String e402PreprocessingRange = 'E402_PREPROCESSING_RANGE';
  static const String e501BufferNotReady = 'E501_BUFFER_NOT_READY';
  static const String e601ModelNotLoaded = 'E601_MODEL_NOT_LOADED';
  static const String e602ModelInputShape = 'E602_MODEL_INPUT_SHAPE';
  static const String e603InferenceFailed = 'E603_INFERENCE_FAILED';
  static const String e604InvalidModelOutput = 'E604_INVALID_MODEL_OUTPUT';
  static const String e701CtcFailed = 'E701_CTC_FAILED';
  static const String e801VocabMismatch = 'E801_VOCAB_MISMATCH';

  static String getDescription(String code) {
    switch (code) {
      case e001ModelAssetNotFound:
        return 'ملف الموديل غير موجود في الأصول (E001_MODEL_ASSET_NOT_FOUND)';
      case e002ModelAssetEmpty:
        return 'ملف الموديل فارغ 0 بايت (E002_MODEL_ASSET_EMPTY)';
      case e010InterpreterCreateFailed:
        return 'فشل إنشاء Interpreter للنموذج (E010_INTERPRETER_CREATE_FAILED)';
      case e011TensorShapeMismatch:
        return 'أبعاد Tensors الحقيقية لا تطابق المتوقع (E011_TENSOR_SHAPE_MISMATCH)';
      case e012StandaloneInferenceFailed:
        return 'فشل تشغيل الاستنتاج المستقل للموديل (E012_STANDALONE_INFERENCE_FAILED)';
      case e020VocabMissingIds:
        return 'قاموس المفردات تنقصه بعض المعرفات (E020_VOCAB_MISSING_IDS)';
      case e101PersonDetectorNotCalled:
        return 'كاشف الشخص لم يتم استدعاؤه رغم وصول إطارات الكاميرا (E101_PERSON_DETECTOR_NOT_CALLED)';
      case e102PersonDetectorException:
        return 'حدث خطأ استثنائي داخل كاشف الشخص (E102_PERSON_DETECTOR_EXCEPTION)';
      case e110ImageConversionFailed:
        return 'فشل تحويل صورة الكاميرا إلى صيغة الكاشف (E110_IMAGE_CONVERSION_FAILED)';
      case e201KeypointCount:
        return 'عدد النقاط لا يساوي 86 نقطة بالضبط (E201_KEYPOINT_COUNT)';
      case e301PreprocessNan:
        return 'المعالجة المسبقة أنتجت قيماً غير معرفة NaN (E301_PREPROCESS_NAN)';
      case e401BufferNotFilling:
        return 'المخزن الزمني لا يمتلئ بالرغم من توفر المعالم (E401_BUFFER_NOT_FILLING)';
      case e501RealModelInputInvalid:
        return 'مصفوفة الدخل الفعلي للنموذج غير صالحة (E501_REAL_MODEL_INPUT_INVALID)';
      case e001CameraNoFrames:
        return 'الكاميرا لا ترسل إطارات أو البث متوقف';
      case e002CameraRotation:
        return 'زاوية دوران الكاميرا أو المستشعر غير صحيحة';
      case e101PersonNotDetected:
        return 'لم يتم رصد وجود شخص أو وضعية جسم أمام الكاميرا';
      case e201NoHand:
        return 'لم يتم رصد أي يد (يمنى أو يسرى) في الإطار';
      default:
        return 'خطأ غير محدد: $code';
    }
  }
}

// ──────────────────────────────── STAGE 1: CAMERA ────────────────────────────────
class CameraDiagnosticData {
  final DiagnosticStageStatus status;
  final bool isInitialized;
  final bool isStreaming;
  final double fps;
  final int frameAgeMs;
  final int width;
  final int height;
  final String format;
  final int rotation;
  final int previewRotation;
  final int detectorInputRotation;
  final int framesReceived;
  final DiagnosticStageStatus imageConversionStatus;
  final String? imageConversionError;
  final int personDetectorCalls;
  final int personDetectorResults;
  final int personDetectorErrors;
  final int poseLandmarks;
  final int faceLandmarks;
  final int leftHandLandmarks;
  final int rightHandLandmarks;
  final DateTime? lastFrameTime;
  final String? errorCode;
  final String? errorMessage;

  const CameraDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.isInitialized = false,
    this.isStreaming = false,
    this.fps = 0.0,
    this.frameAgeMs = 0,
    this.width = 0,
    this.height = 0,
    this.format = 'UNKNOWN',
    this.rotation = 0,
    this.previewRotation = 0,
    this.detectorInputRotation = 0,
    this.framesReceived = 0,
    this.imageConversionStatus = DiagnosticStageStatus.waiting,
    this.imageConversionError,
    this.personDetectorCalls = 0,
    this.personDetectorResults = 0,
    this.personDetectorErrors = 0,
    this.poseLandmarks = 0,
    this.faceLandmarks = 0,
    this.leftHandLandmarks = 0,
    this.rightHandLandmarks = 0,
    this.lastFrameTime,
    this.errorCode,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'isInitialized': isInitialized,
    'isStreaming': isStreaming,
    'fps': fps.toStringAsFixed(1),
    'frameAgeMs': frameAgeMs,
    'resolution': '${width}x$height',
    'format': format,
    'rotation': rotation,
    'previewRotation': previewRotation,
    'detectorInputRotation': detectorInputRotation,
    'framesReceived': framesReceived,
    'imageConversion': imageConversionStatus.name,
    'personDetectorCalls': personDetectorCalls,
    'personDetectorResults': personDetectorResults,
    'personDetectorErrors': personDetectorErrors,
    'poseLandmarks': poseLandmarks,
    'faceLandmarks': faceLandmarks,
    'leftHandLandmarks': leftHandLandmarks,
    'rightHandLandmarks': rightHandLandmarks,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
  };
}

// ──────────────────────────────── STAGE 2: PERSON DETECTION ────────────────────────────────
class PersonDiagnosticData {
  final DiagnosticStageStatus status;
  final bool personPresent;
  final bool posePresent;
  final bool facePresent;
  final bool headPresent;
  final int poseLandmarks;
  final int faceLandmarks;
  final int leftHandLandmarks;
  final int rightHandLandmarks;
  final String? failureReason;
  final String? errorCode;

  const PersonDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.personPresent = false,
    this.posePresent = false,
    this.facePresent = false,
    this.headPresent = false,
    this.poseLandmarks = 0,
    this.faceLandmarks = 0,
    this.leftHandLandmarks = 0,
    this.rightHandLandmarks = 0,
    this.failureReason,
    this.errorCode,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'personPresent': personPresent,
    'posePresent': posePresent,
    'facePresent': facePresent,
    'headPresent': headPresent,
    'poseLandmarks': poseLandmarks,
    'faceLandmarks': faceLandmarks,
    'leftHandLandmarks': leftHandLandmarks,
    'rightHandLandmarks': rightHandLandmarks,
    'failureReason': failureReason,
    'errorCode': errorCode,
  };
}

// ──────────────────────────────── STAGE 3: HAND DETECTION ────────────────────────────────
class HandsDiagnosticData {
  final DiagnosticStageStatus status;
  final bool leftHandDetected;
  final int leftHandLandmarks;
  final double leftHandConfidence;
  final bool rightHandDetected;
  final int rightHandLandmarks;
  final double rightHandConfidence;
  final String? errorCode;
  final String? errorMessage;

  const HandsDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.leftHandDetected = false,
    this.leftHandLandmarks = 0,
    this.leftHandConfidence = 0.0,
    this.rightHandDetected = false,
    this.rightHandLandmarks = 0,
    this.rightHandConfidence = 0.0,
    this.errorCode,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'leftHand': {'detected': leftHandDetected, 'landmarks': leftHandLandmarks, 'confidence': leftHandConfidence},
    'rightHand': {'detected': rightHandDetected, 'landmarks': rightHandLandmarks, 'confidence': rightHandConfidence},
    'errorCode': errorCode,
    'errorMessage': errorMessage,
  };
}

// ──────────────────────────────── STAGE 4: FACE / HEAD / LIPS ────────────────────────────────
class FaceHeadLipsDiagnosticData {
  final DiagnosticStageStatus status;
  final bool faceDetected;
  final bool headDetected;
  final bool lipsDetected;
  final int validFacePoints;
  final int validHeadPoints;
  final int validLipPoints;
  final double confidence;

  const FaceHeadLipsDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.faceDetected = false,
    this.headDetected = false,
    this.lipsDetected = false,
    this.validFacePoints = 0,
    this.validHeadPoints = 0,
    this.validLipPoints = 0,
    this.confidence = 0.0,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'faceDetected': faceDetected,
    'headDetected': headDetected,
    'lipsDetected': lipsDetected,
    'validFacePoints': validFacePoints,
    'validHeadPoints': validHeadPoints,
    'validLipPoints': validLipPoints,
    'confidence': confidence,
  };
}

// ──────────────────────────────── STAGE 5: EXACT 86 KEYPOINTS ────────────────────────────────
class Keypoints86DiagnosticData {
  final DiagnosticStageStatus status;
  final int keypointCount;
  final int validKeypoints;
  final int missingKeypoints;
  final int nanCount;
  final int infinityCount;
  final int zeroCount;
  final String sampleP0;
  final String sampleP1;
  final String sampleP2;
  final String? errorCode;
  final String? errorMessage;

  const Keypoints86DiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.keypointCount = 0,
    this.validKeypoints = 0,
    this.missingKeypoints = 0,
    this.nanCount = 0,
    this.infinityCount = 0,
    this.zeroCount = 0,
    this.sampleP0 = '(0.0, 0.0)',
    this.sampleP1 = '(0.0, 0.0)',
    this.sampleP2 = '(0.0, 0.0)',
    this.errorCode,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'keypointCount': keypointCount,
    'validKeypoints': validKeypoints,
    'missingKeypoints': missingKeypoints,
    'nanCount': nanCount,
    'infinityCount': infinityCount,
    'zeroCount': zeroCount,
    'samples': {'P0': sampleP0, 'P1': sampleP1, 'P2': sampleP2},
    'errorCode': errorCode,
    'errorMessage': errorMessage,
  };
}

// ──────────────────────────────── STAGE 6: POINT GROUP DIAGNOSTICS ────────────────────────────────
class PointGroupDiagnosticData {
  final DiagnosticStageStatus status;
  final int rightHandValid;
  final int rightHandTotal; // 21
  final int leftHandValid;
  final int leftHandTotal; // 21
  final int faceLipValid;
  final int faceLipTotal; // 19
  final int bodyValid;
  final int bodyTotal; // 25
  final String? errorCode;
  final String? errorMessage;

  const PointGroupDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.rightHandValid = 0,
    this.rightHandTotal = 21,
    this.leftHandValid = 0,
    this.leftHandTotal = 21,
    this.faceLipValid = 0,
    this.faceLipTotal = 19,
    this.bodyValid = 0,
    this.bodyTotal = 25,
    this.errorCode,
    this.errorMessage,
  });

  int get totalHandValid => rightHandValid + leftHandValid;
  int get totalHandExpected => rightHandTotal + leftHandTotal; // 42

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'rightHand': '$rightHandValid/$rightHandTotal',
    'leftHand': '$leftHandValid/$leftHandTotal',
    'handsTotal': '$totalHandValid/$totalHandExpected',
    'faceLips': '$faceLipValid/$faceLipTotal',
    'body': '$bodyValid/$bodyTotal',
    'errorCode': errorCode,
    'errorMessage': errorMessage,
  };
}

// ──────────────────────────────── STAGE 7: PREPROCESSING ────────────────────────────────
class PreprocessingDiagnosticData {
  final DiagnosticStageStatus status;
  final double rawMinX;
  final double rawMaxX;
  final double rawMinY;
  final double rawMaxY;
  final double normMin;
  final double normMax;
  final double normMean;
  final bool hasNan;
  final bool hasInfinity;
  final bool hasExtremeValues;
  final String? errorCode;
  final String? errorMessage;

  const PreprocessingDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.rawMinX = 0.0,
    this.rawMaxX = 0.0,
    this.rawMinY = 0.0,
    this.rawMaxY = 0.0,
    this.normMin = 0.0,
    this.normMax = 0.0,
    this.normMean = 0.0,
    this.hasNan = false,
    this.hasInfinity = false,
    this.hasExtremeValues = false,
    this.errorCode,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'rawRange': {'minX': rawMinX, 'maxX': rawMaxX, 'minY': rawMinY, 'maxY': rawMaxY},
    'normStats': {'min': normMin, 'max': normMax, 'mean': normMean},
    'hasNan': hasNan,
    'hasInfinity': hasInfinity,
    'hasExtremeValues': hasExtremeValues,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
  };
}

// ──────────────────────────────── STAGE 8: TEMPORAL BUFFER ────────────────────────────────
class TemporalBufferDiagnosticData {
  final DiagnosticStageStatus status;
  final int currentFrames;
  final int requiredFrames; // 128
  final int validFrames;
  final int invalidFrames;
  final int personFrames;
  final int handFrames;
  final int headFrames;
  final String? errorCode;
  final String? errorMessage;

  const TemporalBufferDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.currentFrames = 0,
    this.requiredFrames = 128,
    this.validFrames = 0,
    this.invalidFrames = 0,
    this.personFrames = 0,
    this.handFrames = 0,
    this.headFrames = 0,
    this.errorCode,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'bufferFill': '$currentFrames/$requiredFrames',
    'validFrames': validFrames,
    'invalidFrames': invalidFrames,
    'personFrames': personFrames,
    'handFrames': handFrames,
    'headFrames': headFrames,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
  };
}

// ──────────────────────────────── STAGE 9: EXACT MODEL INPUT ────────────────────────────────
class ModelInputDiagnosticData {
  final DiagnosticStageStatus status;
  final List<int> shape;
  final String dtype;
  final int totalValues; // 1 * 128 * 86 * 2 = 22016
  final double min;
  final double max;
  final double mean;
  final int nanCount;
  final double zeroPercentage;
  final String? errorCode;
  final String? errorMessage;

  const ModelInputDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.shape = const [1, 128, 86, 2],
    this.dtype = 'float32',
    this.totalValues = 0,
    this.min = 0.0,
    this.max = 0.0,
    this.mean = 0.0,
    this.nanCount = 0,
    this.zeroPercentage = 0.0,
    this.errorCode,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'shape': shape,
    'dtype': dtype,
    'totalValues': totalValues,
    'min': min,
    'max': max,
    'mean': mean,
    'nanCount': nanCount,
    'zeroPercentage': '${zeroPercentage.toStringAsFixed(1)}%',
    'errorCode': errorCode,
    'errorMessage': errorMessage,
  };
}

// ──────────────────────────────── STAGE 10: TFLITE LOADING ────────────────────────────────
class TfliteLoadDiagnosticData {
  final DiagnosticStageStatus status;
  final bool fileFound;
  final bool isLoaded;
  final DiagnosticStageStatus modelFileStatus;
  final int modelSizeBytes;
  final double modelSizeMb;
  final DiagnosticStageStatus interpreterStatus;
  final DiagnosticStageStatus inputTensorStatus;
  final DiagnosticStageStatus outputTensorStatus;
  final DiagnosticStageStatus standaloneInferenceStatus;
  final int standaloneInferenceTimeMs;
  final List<int>? inputShape;
  final List<int>? outputShape;
  final String inputType;
  final String outputType;
  final String? exceptionType;
  final String? exceptionMessage;
  final String? errorCode;
  final String? errorMessage;

  const TfliteLoadDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.fileFound = false,
    this.isLoaded = false,
    this.modelFileStatus = DiagnosticStageStatus.waiting,
    this.modelSizeBytes = 0,
    this.modelSizeMb = 0.0,
    this.interpreterStatus = DiagnosticStageStatus.waiting,
    this.inputTensorStatus = DiagnosticStageStatus.waiting,
    this.outputTensorStatus = DiagnosticStageStatus.waiting,
    this.standaloneInferenceStatus = DiagnosticStageStatus.waiting,
    this.standaloneInferenceTimeMs = 0,
    this.inputShape,
    this.outputShape,
    this.inputType = 'float32',
    this.outputType = 'float32',
    this.exceptionType,
    this.exceptionMessage,
    this.errorCode,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'fileFound': fileFound,
    'isLoaded': isLoaded,
    'modelFileStatus': modelFileStatus.name,
    'modelSizeBytes': modelSizeBytes,
    'modelSizeMb': modelSizeMb.toStringAsFixed(2),
    'interpreterStatus': interpreterStatus.name,
    'inputTensorStatus': inputTensorStatus.name,
    'outputTensorStatus': outputTensorStatus.name,
    'standaloneInferenceStatus': standaloneInferenceStatus.name,
    'standaloneInferenceTimeMs': standaloneInferenceTimeMs,
    'inputShape': inputShape,
    'outputShape': outputShape,
    'inputType': inputType,
    'outputType': outputType,
    'exceptionType': exceptionType,
    'exceptionMessage': exceptionMessage,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
  };
}

// ──────────────────────────────── STAGE 11: INFERENCE ────────────────────────────────
class InferenceDiagnosticData {
  final DiagnosticStageStatus status;
  final int inferenceTimeMs;
  final String? exceptionType;
  final String? exceptionMessage;
  final String? stackTraceSnippet;
  final String? errorCode;

  const InferenceDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.inferenceTimeMs = 0,
    this.exceptionType,
    this.exceptionMessage,
    this.stackTraceSnippet,
    this.errorCode,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'inferenceTimeMs': inferenceTimeMs,
    'exceptionType': exceptionType,
    'exceptionMessage': exceptionMessage,
    'errorCode': errorCode,
  };
}

// ──────────────────────────────── STAGE 12: MODEL OUTPUT VALIDATION ────────────────────────────────
class ModelOutputDiagnosticData {
  final DiagnosticStageStatus status;
  final List<int> outputShape;
  final int nanCount;
  final int infinityCount;
  final bool isAllZeros;
  final double min;
  final double max;
  final double mean;
  final String? errorCode;
  final String? errorMessage;

  const ModelOutputDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.outputShape = const [1, 29, 684],
    this.nanCount = 0,
    this.infinityCount = 0,
    this.isAllZeros = false,
    this.min = 0.0,
    this.max = 0.0,
    this.mean = 0.0,
    this.errorCode,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'shape': outputShape,
    'nanCount': nanCount,
    'infinityCount': infinityCount,
    'isAllZeros': isAllZeros,
    'stats': {'min': min, 'max': max, 'mean': mean},
    'errorCode': errorCode,
    'errorMessage': errorMessage,
  };
}

// ──────────────────────────────── STAGE 13: RAW TOP CLASSES ────────────────────────────────
class TopClassItem {
  final int rank;
  final int classId;
  final String gloss;
  final double score;

  const TopClassItem({
    required this.rank,
    required this.classId,
    required this.gloss,
    required this.score,
  });

  Map<String, dynamic> toMap() => {
    'rank': rank,
    'classId': classId,
    'gloss': gloss,
    'score': '${(score * 100).toStringAsFixed(1)}%',
  };
}

class RawTopClassesDiagnosticData {
  final DiagnosticStageStatus status;
  final List<TopClassItem> top5;
  final double blankRatio;
  final bool isBlankDominant;

  const RawTopClassesDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.top5 = const [],
    this.blankRatio = 0.0,
    this.isBlankDominant = false,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'top5': top5.map((c) => c.toMap()).toList(),
    'blankRatio': '${(blankRatio * 100).toStringAsFixed(1)}%',
    'isBlankDominant': isBlankDominant,
  };
}

// ──────────────────────────────── STAGE 14: CTC ────────────────────────────────
class CtcDiagnosticData {
  final DiagnosticStageStatus status;
  final List<int> rawIds;
  final List<int> collapsedIds;
  final List<int> afterBlankRemovalIds;
  final List<String> decodedGlosses;
  final double averageConfidence;
  final String? errorCode;
  final String? errorMessage;

  const CtcDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.rawIds = const [],
    this.collapsedIds = const [],
    this.afterBlankRemovalIds = const [],
    this.decodedGlosses = const [],
    this.averageConfidence = 0.0,
    this.errorCode,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'rawIds': rawIds,
    'collapsedIds': collapsedIds,
    'afterBlankRemovalIds': afterBlankRemovalIds,
    'decodedGlosses': decodedGlosses,
    'confidence': averageConfidence,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
  };
}

// ──────────────────────────────── STAGE 15: VOCABULARY ────────────────────────────────
class VocabularyDiagnosticData {
  final DiagnosticStageStatus status;
  final int totalClasses; // 684
  final bool isValid;
  final List<String> verifiedMappings; // e.g. ["ID 312 -> مساعدة"]
  final List<int> invalidIds;
  final String? errorCode;
  final String? errorMessage;

  const VocabularyDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.totalClasses = 684,
    this.isValid = false,
    this.verifiedMappings = const [],
    this.invalidIds = const [],
    this.errorCode,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'totalClasses': totalClasses,
    'isValid': isValid,
    'mappings': verifiedMappings,
    'invalidIds': invalidIds,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
  };
}

// ──────────────────────────────── STAGE 16: FINAL OUTPUT ────────────────────────────────
class FinalOutputDiagnosticData {
  final DiagnosticStageStatus status;
  final String? rawModelGloss;
  final String? finalGloss;
  final bool isConfirmed;
  final String decision; // 'CONFIRMED' / 'REJECTED' / 'WAITING'
  final String? rejectionReason;

  const FinalOutputDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.rawModelGloss,
    this.finalGloss,
    this.isConfirmed = false,
    this.decision = 'WAITING',
    this.rejectionReason,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'rawModelGloss': rawModelGloss,
    'finalGloss': finalGloss,
    'decision': decision,
    'isConfirmed': isConfirmed,
    'rejectionReason': rejectionReason,
  };
}

// ──────────────────────────────── EVENT & SNAPSHOT ────────────────────────────────
class DiagnosticEvent {
  final DateTime timestamp;
  final String stage;
  final DiagnosticStageStatus status;
  final String? errorCode;
  final String message;

  const DiagnosticEvent({
    required this.timestamp,
    required this.stage,
    required this.status,
    this.errorCode,
    required this.message,
  });

  String get timeFormatted {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  String toString() {
    final errStr = errorCode != null ? ' [$errorCode]' : '';
    return '$timeFormatted $stage ${status.displayText}$errStr $message';
  }

  Map<String, dynamic> toMap() => {
    'time': timeFormatted,
    'stage': stage,
    'status': status.name,
    'errorCode': errorCode,
    'message': message,
  };
}

/// لقطة تجميد الحالة الكاملة (Freeze Snapshot)
class DiagnosticSnapshot {
  final DateTime capturedAt;
  final CameraDiagnosticData camera;
  final PersonDiagnosticData person;
  final HandsDiagnosticData hands;
  final FaceHeadLipsDiagnosticData faceHead;
  final Keypoints86DiagnosticData keypoints;
  final PointGroupDiagnosticData pointGroups;
  final PreprocessingDiagnosticData preprocessing;
  final TemporalBufferDiagnosticData buffer;
  final ModelInputDiagnosticData modelInput;
  final TfliteLoadDiagnosticData tfliteLoad;
  final InferenceDiagnosticData inference;
  final ModelOutputDiagnosticData modelOutput;
  final RawTopClassesDiagnosticData rawTopClasses;
  final CtcDiagnosticData ctc;
  final VocabularyDiagnosticData vocabulary;
  final FinalOutputDiagnosticData finalOutput;
  final List<DiagnosticEvent> recentEvents;

  const DiagnosticSnapshot({
    required this.capturedAt,
    required this.camera,
    required this.person,
    required this.hands,
    required this.faceHead,
    required this.keypoints,
    required this.pointGroups,
    required this.preprocessing,
    required this.buffer,
    required this.modelInput,
    required this.tfliteLoad,
    required this.inference,
    required this.modelOutput,
    required this.rawTopClasses,
    required this.ctc,
    required this.vocabulary,
    required this.finalOutput,
    required this.recentEvents,
  });

  String toFormattedText() {
    final b = StringBuffer();
    b.writeln('================================================================');
    b.writeln('              ISHARA DIAGNOSTIC SNAPSHOT REPORT                 ');
    b.writeln('Captured At: ${capturedAt.toIso8601String()}');
    b.writeln('================================================================');
    b.writeln('--- MODEL SECTION ---');
    b.writeln('MODEL FILE:              ${tfliteLoad.modelFileStatus.displayText} (${tfliteLoad.modelSizeBytes} bytes, ${tfliteLoad.modelSizeMb.toStringAsFixed(2)} MB)');
    b.writeln('INTERPRETER:             ${tfliteLoad.interpreterStatus.displayText}');
    if (tfliteLoad.exceptionMessage != null) b.writeln('   Interpreter Error: ${tfliteLoad.exceptionType}: ${tfliteLoad.exceptionMessage}');
    b.writeln('INPUT TENSOR:            ${tfliteLoad.inputTensorStatus.displayText} (Actual: ${tfliteLoad.inputShape} vs Expected: [1, 128, 86, 2])');
    b.writeln('OUTPUT TENSOR:           ${tfliteLoad.outputTensorStatus.displayText} (Actual: ${tfliteLoad.outputShape} vs Expected: [1, 29, 684])');
    b.writeln('STANDALONE INFERENCE:    ${tfliteLoad.standaloneInferenceStatus.displayText} (${tfliteLoad.standaloneInferenceTimeMs} ms)');
    b.writeln('MODEL OUTPUT:            ${modelOutput.status.displayText} (NaN: ${modelOutput.nanCount}, Inf: ${modelOutput.infinityCount}, Min: ${modelOutput.min.toStringAsFixed(2)}, Max: ${modelOutput.max.toStringAsFixed(2)})');
    b.writeln('VOCABULARY:              ${vocabulary.status.displayText} (Classes: ${vocabulary.totalClasses}/684, CTC Blank ID: 0)');
    b.writeln('');
    b.writeln('--- CAMERA SECTION ---');
    b.writeln('CAMERA:                  ${camera.status.displayText} (${camera.fps.toStringAsFixed(1)} FPS, ${camera.width}x${camera.height}, age: ${camera.frameAgeMs}ms)');
    b.writeln('FRAMES RECEIVED:         ${camera.framesReceived}');
    b.writeln('IMAGE CONVERSION:        ${camera.imageConversionStatus.displayText}');
    if (camera.imageConversionError != null) b.writeln('   Image Error: ${camera.imageConversionError}');
    b.writeln('PERSON DETECTOR CALLS:   ${camera.personDetectorCalls}');
    b.writeln('PERSON DETECTOR RESULTS: ${camera.personDetectorResults}');
    b.writeln('PERSON DETECTOR ERRORS:  ${camera.personDetectorErrors}');
    b.writeln('PERSON:                  ${person.status.displayText} (Present: ${person.personPresent})');
    b.writeln('POSE:                    [${camera.poseLandmarks} landmarks]');
    b.writeln('FACE:                    [${camera.faceLandmarks} landmarks]');
    b.writeln('LEFT HAND:               [${camera.leftHandLandmarks} landmarks]');
    b.writeln('RIGHT HAND:              [${camera.rightHandLandmarks} landmarks]');
    b.writeln('PREVIEW ROTATION:        ${camera.previewRotation} degrees');
    b.writeln('DETECTOR INPUT ROTATION: ${camera.detectorInputRotation} degrees');
    b.writeln('');
    b.writeln('--- SIGN PIPELINE ---');
    b.writeln('KEYPOINTS:               [${keypoints.validKeypoints} / 86]');
    b.writeln('PREPROCESSING:           ${preprocessing.status.displayText}');
    b.writeln('BUFFER:                  [${buffer.currentFrames} / 128]');
    b.writeln('REAL INPUT:              ${modelInput.status.displayText}');
    b.writeln('REAL INFERENCE:          ${inference.status.displayText} (${inference.inferenceTimeMs} ms)');
    b.writeln('CTC:                     ${ctc.status.displayText} (Raw: ${ctc.rawIds} -> Clean: ${ctc.afterBlankRemovalIds})');
    b.writeln('FINAL GLOSS:             ${finalOutput.finalGloss ?? "NONE"}');
    b.writeln('================================================================');
    b.writeln('RECENT DIAGNOSTIC EVENTS (Last ${recentEvents.length}):');
    for (final e in recentEvents) {
      b.writeln('  $e');
    }
    b.writeln('================================================================');
    return b.toString();
  }

  String toJsonString() {
    final map = {
      'capturedAt': capturedAt.toIso8601String(),
      'camera': camera.toMap(),
      'person': person.toMap(),
      'hands': hands.toMap(),
      'faceHead': faceHead.toMap(),
      'keypoints': keypoints.toMap(),
      'pointGroups': pointGroups.toMap(),
      'preprocessing': preprocessing.toMap(),
      'buffer': buffer.toMap(),
      'modelInput': modelInput.toMap(),
      'tfliteLoad': tfliteLoad.toMap(),
      'inference': inference.toMap(),
      'modelOutput': modelOutput.toMap(),
      'rawTopClasses': rawTopClasses.toMap(),
      'ctc': ctc.toMap(),
      'vocabulary': vocabulary.toMap(),
      'finalOutput': finalOutput.toMap(),
      'events': recentEvents.map((e) => e.toMap()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }
}
