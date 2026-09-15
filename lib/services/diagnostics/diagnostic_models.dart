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
  static const String e001CameraNoFrames = 'E001_CAMERA_NO_FRAMES';
  static const String e002CameraRotation = 'E002_CAMERA_ROTATION';
  static const String e101PersonNotDetected = 'E101_PERSON_NOT_DETECTED';
  static const String e201NoHand = 'E201_NO_HAND';
  static const String e301KeypointCount = 'E301_KEYPOINT_COUNT';
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
      case e001CameraNoFrames:
        return 'الكاميرا لا ترسل إطارات أو البث متوقف';
      case e002CameraRotation:
        return 'زاوية دوران الكاميرا أو المستشعر غير صحيحة';
      case e101PersonNotDetected:
        return 'لم يتم رصد وجود شخص أو وضعية جسم أمام الكاميرا';
      case e201NoHand:
        return 'لم يتم رصد أي يد (يمنى أو يسرى) في الإطار';
      case e301KeypointCount:
        return 'عدد النقاط لا يساوي 86 نقطة بالضبط';
      case e302InvalidKeypointValues:
        return 'إحداثيات النقاط تحتوي على قيم NaN أو مالانهاية';
      case e303MappingFailure:
        return 'فشل خريطة النقاط لمجموعات الأيدي أو الشفاه أو الجسم';
      case e401PreprocessingNan:
        return 'المعالجة المسبقة والتطبيع أنتجت قيماً غير معرفة (NaN)';
      case e402PreprocessingRange:
        return 'القيم بعد التطبيع خارج النطاق الطبيعي المتوقع';
      case e501BufferNotReady:
        return 'المخزن الزمني لم يكتمل بعد (أقل من 128 إطاراً)';
      case e601ModelNotLoaded:
        return 'تعذر تحميل ملف النموذج ishara_model.tflite';
      case e602ModelInputShape:
        return 'أبعاد مصفوفة دخل النموذج غير مطابقة [1, 128, 86, 2]';
      case e603InferenceFailed:
        return 'فشل استدعاء وتشغيل استنتاج TFLite interpreter';
      case e604InvalidModelOutput:
        return 'مخرجات النموذج لا تطابق [1, 29, 684] أو تحتوي NaN';
      case e701CtcFailed:
        return 'فشل فك ترميز CTC أو إنتاج تسلسل فارغ';
      case e801VocabMismatch:
        return 'معرف الفئة خارج حدود قاموس المفردات (0..683)';
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
  final String? failureReason;
  final String? errorCode;

  const PersonDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.personPresent = false,
    this.posePresent = false,
    this.facePresent = false,
    this.headPresent = false,
    this.failureReason,
    this.errorCode,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'personPresent': personPresent,
    'posePresent': posePresent,
    'facePresent': facePresent,
    'headPresent': headPresent,
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
  final List<int>? inputShape;
  final List<int>? outputShape;
  final String inputType;
  final String outputType;
  final String? errorCode;
  final String? errorMessage;

  const TfliteLoadDiagnosticData({
    this.status = DiagnosticStageStatus.waiting,
    this.fileFound = false,
    this.isLoaded = false,
    this.inputShape,
    this.outputShape,
    this.inputType = 'float32',
    this.outputType = 'float32',
    this.errorCode,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'fileFound': fileFound,
    'isLoaded': isLoaded,
    'inputShape': inputShape,
    'outputShape': outputShape,
    'inputType': inputType,
    'outputType': outputType,
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
    b.writeln('STAGE 1 — CAMERA:          ${camera.status.displayText} (${camera.fps.toStringAsFixed(1)} FPS, ${camera.width}x${camera.height}, age: ${camera.frameAgeMs}ms)');
    if (camera.errorCode != null) b.writeln('   Error: ${camera.errorCode} - ${camera.errorMessage}');
    b.writeln('STAGE 2 — PERSON:          ${person.status.displayText} (person=${person.personPresent}, pose=${person.posePresent}, head=${person.headPresent})');
    if (person.errorCode != null) b.writeln('   Error: ${person.errorCode} - ${person.failureReason}');
    b.writeln('STAGE 3 — HANDS:           ${hands.status.displayText} (L: ${hands.leftHandLandmarks} lms, R: ${hands.rightHandLandmarks} lms)');
    b.writeln('STAGE 4 — FACE/HEAD/LIPS:  ${faceHead.status.displayText} (Head: ${faceHead.validHeadPoints}/25, Face: ${faceHead.validFacePoints}, Lips: ${faceHead.validLipPoints}/19)');
    b.writeln('STAGE 5 — 86 KEYPOINTS:    ${keypoints.status.displayText} (Count: ${keypoints.keypointCount}/86, Valid: ${keypoints.validKeypoints}, Missing: ${keypoints.missingKeypoints})');
    b.writeln('   Sample: P0=${keypoints.sampleP0}, P1=${keypoints.sampleP1}, P2=${keypoints.sampleP2}');
    b.writeln('STAGE 6 — POINT GROUPS:    ${pointGroups.status.displayText} (Hands: ${pointGroups.totalHandValid}/42, Lips: ${pointGroups.faceLipValid}/19, Body: ${pointGroups.bodyValid}/25)');
    b.writeln('STAGE 7 — PREPROCESSING:   ${preprocessing.status.displayText} (Raw: [${preprocessing.rawMinX.toStringAsFixed(2)}..${preprocessing.rawMaxX.toStringAsFixed(2)}], Norm: [${preprocessing.normMin.toStringAsFixed(2)}..${preprocessing.normMax.toStringAsFixed(2)}])');
    b.writeln('STAGE 8 — BUFFER:          ${buffer.status.displayText} (${buffer.currentFrames}/${buffer.requiredFrames} frames, person: ${buffer.personFrames}, hands: ${buffer.handFrames})');
    b.writeln('STAGE 9 — MODEL INPUT:     ${modelInput.status.displayText} (Shape: ${modelInput.shape}, ${modelInput.totalValues} values, zeros: ${modelInput.zeroPercentage.toStringAsFixed(1)}%)');
    b.writeln('STAGE 10 — TFLITE LOAD:    ${tfliteLoad.status.displayText} (In: ${tfliteLoad.inputShape}, Out: ${tfliteLoad.outputShape})');
    b.writeln('STAGE 11 — INFERENCE:      ${inference.status.displayText} (${inference.inferenceTimeMs} ms)');
    if (inference.exceptionMessage != null) b.writeln('   Exception: ${inference.exceptionType}: ${inference.exceptionMessage}');
    b.writeln('STAGE 12 — MODEL OUTPUT:   ${modelOutput.status.displayText} (Shape: ${modelOutput.outputShape}, NaN: ${modelOutput.nanCount})');
    b.writeln('STAGE 13 — RAW TOP CLASSES:');
    for (final c in rawTopClasses.top5) {
      b.writeln('   #${c.rank}: ID ${c.classId} -> "${c.gloss}" (${(c.score * 100).toStringAsFixed(1)}%)');
    }
    b.writeln('STAGE 14 — CTC DECODER:    ${ctc.status.displayText} (Raw: ${ctc.rawIds} -> Collapsed: ${ctc.collapsedIds} -> Clean: ${ctc.afterBlankRemovalIds})');
    b.writeln('STAGE 15 — VOCABULARY:     ${vocabulary.status.displayText} (${vocabulary.totalClasses} classes, valid=${vocabulary.isValid})');
    b.writeln('STAGE 16 — FINAL GLOSS:    ${finalOutput.status.displayText} (Raw: "${finalOutput.rawModelGloss}", Decision: ${finalOutput.decision}, Final: "${finalOutput.finalGloss}")');
    if (finalOutput.rejectionReason != null) b.writeln('   Rejection Reason: ${finalOutput.rejectionReason}');
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
