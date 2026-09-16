import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:ishara/services/diagnostics/diagnostic_models.dart';

/// IsharaDiagnosticService
/// محرك التشخيص الشامل لجميع مراحل الـ Pipeline من الكاميرا وحتى ترجمة الإشارة.
class IsharaDiagnosticService extends ChangeNotifier {
  static final IsharaDiagnosticService _instance =
      IsharaDiagnosticService._internal();
  factory IsharaDiagnosticService() => _instance;
  IsharaDiagnosticService._internal();

  // تجميد اللقطة (Freeze Mode)
  bool _isFrozen = false;
  DiagnosticSnapshot? _frozenSnapshot;

  bool get isFrozen => _isFrozen;
  DiagnosticSnapshot? get frozenSnapshot => _frozenSnapshot;

  // سجل الأحداث الـ 50 الأخيرة (Circular Buffer)
  static const int maxEvents = 50;
  final ListQueue<DiagnosticEvent> _eventHistory = ListQueue<DiagnosticEvent>(
    maxEvents,
  );

  List<DiagnosticEvent> get eventHistory => List.unmodifiable(_eventHistory);

  // حالات المراحل التشخيصية الـ 16
  CameraDiagnosticData _camera = const CameraDiagnosticData();
  PersonDiagnosticData _person = const PersonDiagnosticData();
  HandsDiagnosticData _hands = const HandsDiagnosticData();
  FaceHeadLipsDiagnosticData _faceHead = const FaceHeadLipsDiagnosticData();
  Keypoints86DiagnosticData _keypoints = const Keypoints86DiagnosticData();
  PointGroupDiagnosticData _pointGroups = const PointGroupDiagnosticData();
  PreprocessingDiagnosticData _preprocessing =
      const PreprocessingDiagnosticData();
  TemporalBufferDiagnosticData _buffer = const TemporalBufferDiagnosticData();
  ModelInputDiagnosticData _modelInput = const ModelInputDiagnosticData();
  TfliteLoadDiagnosticData _tfliteLoad = const TfliteLoadDiagnosticData();
  InferenceDiagnosticData _inference = const InferenceDiagnosticData();
  ModelOutputDiagnosticData _modelOutput = const ModelOutputDiagnosticData();
  RawTopClassesDiagnosticData _rawTopClasses =
      const RawTopClassesDiagnosticData();
  CtcDiagnosticData _ctc = const CtcDiagnosticData();
  VocabularyDiagnosticData _vocabulary = const VocabularyDiagnosticData();
  FinalOutputDiagnosticData _finalOutput = const FinalOutputDiagnosticData();

  // Getters
  CameraDiagnosticData get camera =>
      _isFrozen && _frozenSnapshot != null ? _frozenSnapshot!.camera : _camera;
  PersonDiagnosticData get person =>
      _isFrozen && _frozenSnapshot != null ? _frozenSnapshot!.person : _person;
  HandsDiagnosticData get hands =>
      _isFrozen && _frozenSnapshot != null ? _frozenSnapshot!.hands : _hands;
  FaceHeadLipsDiagnosticData get faceHead =>
      _isFrozen && _frozenSnapshot != null
      ? _frozenSnapshot!.faceHead
      : _faceHead;
  Keypoints86DiagnosticData get keypoints =>
      _isFrozen && _frozenSnapshot != null
      ? _frozenSnapshot!.keypoints
      : _keypoints;
  PointGroupDiagnosticData get pointGroups =>
      _isFrozen && _frozenSnapshot != null
      ? _frozenSnapshot!.pointGroups
      : _pointGroups;
  PreprocessingDiagnosticData get preprocessing =>
      _isFrozen && _frozenSnapshot != null
      ? _frozenSnapshot!.preprocessing
      : _preprocessing;
  TemporalBufferDiagnosticData get buffer =>
      _isFrozen && _frozenSnapshot != null ? _frozenSnapshot!.buffer : _buffer;
  ModelInputDiagnosticData get modelInput =>
      _isFrozen && _frozenSnapshot != null
      ? _frozenSnapshot!.modelInput
      : _modelInput;
  TfliteLoadDiagnosticData get tfliteLoad =>
      _isFrozen && _frozenSnapshot != null
      ? _frozenSnapshot!.tfliteLoad
      : _tfliteLoad;
  InferenceDiagnosticData get inference => _isFrozen && _frozenSnapshot != null
      ? _frozenSnapshot!.inference
      : _inference;
  ModelOutputDiagnosticData get modelOutput =>
      _isFrozen && _frozenSnapshot != null
      ? _frozenSnapshot!.modelOutput
      : _modelOutput;
  RawTopClassesDiagnosticData get rawTopClasses =>
      _isFrozen && _frozenSnapshot != null
      ? _frozenSnapshot!.rawTopClasses
      : _rawTopClasses;
  CtcDiagnosticData get ctc =>
      _isFrozen && _frozenSnapshot != null ? _frozenSnapshot!.ctc : _ctc;
  VocabularyDiagnosticData get vocabulary =>
      _isFrozen && _frozenSnapshot != null
      ? _frozenSnapshot!.vocabulary
      : _vocabulary;
  FinalOutputDiagnosticData get finalOutput =>
      _isFrozen && _frozenSnapshot != null
      ? _frozenSnapshot!.finalOutput
      : _finalOutput;

  void _recordEvent(
    String stage,
    DiagnosticStageStatus status,
    String message, {
    String? errorCode,
  }) {
    final event = DiagnosticEvent(
      timestamp: DateTime.now(),
      stage: stage,
      status: status,
      errorCode: errorCode,
      message: message,
    );
    if (_eventHistory.length >= maxEvents) {
      _eventHistory.removeFirst();
    }
    _eventHistory.addLast(event);
  }

  // ──────────────────────────── FREEZE CONTROL ────────────────────────────
  void toggleFreeze() {
    if (_isFrozen) {
      _isFrozen = false;
      _frozenSnapshot = null;
    } else {
      _isFrozen = true;
      _frozenSnapshot = takeSnapshot();
    }
    notifyListeners();
  }

  DiagnosticSnapshot takeSnapshot() {
    return DiagnosticSnapshot(
      capturedAt: DateTime.now(),
      camera: _camera,
      person: _person,
      hands: _hands,
      faceHead: _faceHead,
      keypoints: _keypoints,
      pointGroups: _pointGroups,
      preprocessing: _preprocessing,
      buffer: _buffer,
      modelInput: _modelInput,
      tfliteLoad: _tfliteLoad,
      inference: _inference,
      modelOutput: _modelOutput,
      rawTopClasses: _rawTopClasses,
      ctc: _ctc,
      vocabulary: _vocabulary,
      finalOutput: _finalOutput,
      recentEvents: List.from(_eventHistory),
    );
  }

  // ──────────────────────────── 1. CAMERA ────────────────────────────
  void recordCamera({
    required bool isInitialized,
    required bool isStreaming,
    required double fps,
    required int frameAgeMs,
    required int width,
    required int height,
    required String format,
    required int rotation,
    int previewRotation = 0,
    int detectorInputRotation = 0,
    int framesReceived = 0,
    DiagnosticStageStatus imageConversionStatus = DiagnosticStageStatus.pass,
    String? imageConversionError,
    int personDetectorCalls = 0,
    int personDetectorResults = 0,
    int personDetectorErrors = 0,
    int poseLandmarks = 0,
    int faceLandmarks = 0,
    int leftHandLandmarks = 0,
    int rightHandLandmarks = 0,
  }) {
    if (_isFrozen) return;

    final bool ok =
        isInitialized &&
        isStreaming &&
        frameAgeMs < 1500 &&
        width > 0 &&
        height > 0;
    final String? errCode = !isStreaming || frameAgeMs >= 1500
        ? DiagnosticErrorCodes.e001CameraNoFrames
        : (rotation % 90 != 0 ? DiagnosticErrorCodes.e002CameraRotation : null);

    _camera = CameraDiagnosticData(
      status: ok ? DiagnosticStageStatus.pass : DiagnosticStageStatus.fail,
      isInitialized: isInitialized,
      isStreaming: isStreaming,
      fps: fps,
      frameAgeMs: frameAgeMs,
      width: width,
      height: height,
      format: format,
      rotation: rotation,
      previewRotation: previewRotation,
      detectorInputRotation: detectorInputRotation,
      framesReceived: framesReceived,
      imageConversionStatus: imageConversionStatus,
      imageConversionError: imageConversionError,
      personDetectorCalls: personDetectorCalls,
      personDetectorResults: personDetectorResults,
      personDetectorErrors: personDetectorErrors,
      poseLandmarks: poseLandmarks,
      faceLandmarks: faceLandmarks,
      leftHandLandmarks: leftHandLandmarks,
      rightHandLandmarks: rightHandLandmarks,
      lastFrameTime: DateTime.now(),
      errorCode: errCode,
      errorMessage: errCode != null
          ? DiagnosticErrorCodes.getDescription(errCode)
          : null,
    );

    if (!ok) {
      _recordEvent(
        'CAMERA',
        DiagnosticStageStatus.fail,
        'No frames arriving or stream halted ($frameAgeMs ms)',
        errorCode: errCode,
      );
    }
    notifyListeners();
  }

  // ──────────────────────────── 2. PERSON DETECTION ────────────────────────────
  void recordPerson({
    required bool personPresent,
    required bool posePresent,
    required bool facePresent,
    required bool headPresent,
    int poseLandmarks = 0,
    int faceLandmarks = 0,
    int leftHandLandmarks = 0,
    int rightHandLandmarks = 0,
    String? reason,
  }) {
    if (_isFrozen) return;

    final bool ok = personPresent;
    String? failureReason = reason;
    String? errCode;

    if (!ok) {
      errCode = DiagnosticErrorCodes.e101PersonNotDetected;
      failureReason ??= (!posePresent
          ? 'NO_POSE_LANDMARKS'
          : (!headPresent
                ? 'NO_HEAD_RESULT'
                : (!facePresent ? 'NO_FACE_RESULT' : 'FRAME_NOT_PROCESSED')));
      _recordEvent(
        'PERSON',
        DiagnosticStageStatus.fail,
        failureReason,
        errorCode: errCode,
      );
    }

    _person = PersonDiagnosticData(
      status: ok ? DiagnosticStageStatus.pass : DiagnosticStageStatus.fail,
      personPresent: personPresent,
      posePresent: posePresent,
      facePresent: facePresent,
      headPresent: headPresent,
      poseLandmarks: poseLandmarks,
      faceLandmarks: faceLandmarks,
      leftHandLandmarks: leftHandLandmarks,
      rightHandLandmarks: rightHandLandmarks,
      failureReason: failureReason,
      errorCode: errCode,
    );

    notifyListeners();
  }

  // ──────────────────────────── 3. HAND DETECTION ────────────────────────────
  void recordHands({
    required bool leftHandDetected,
    required int leftHandLandmarks,
    required double leftHandConfidence,
    required bool rightHandDetected,
    required int rightHandLandmarks,
    required double rightHandConfidence,
    int handDetectorCalls = 0,
    int handDetectorResults = 0,
    int handDetectorErrors = 0,
    int leftHandResults = 0,
    int rightHandResults = 0,
    DiagnosticStageStatus? staticHandTestStatus,
    int? staticHandsDetected,
    int? staticHandLandmarks,
    double? staticHandConfidence,
    String? exceptionType,
    String? stackTraceSnippet,
    String? errorMessage,
  }) {
    if (_isFrozen) return;

    final bool hasAnyHand = leftHandDetected || rightHandDetected;
    String? errCode;
    String? errMsg = errorMessage;

    if (handDetectorErrors > 0) {
      errCode = DiagnosticErrorCodes.e203HandDetectorException;
      errMsg ??= 'Hand detector threw exception: $exceptionType';
    } else if (handDetectorCalls == 0 && _camera.framesReceived > 0) {
      errCode = DiagnosticErrorCodes.e202HandDetectorNotCalled;
      errMsg ??= 'Hand detector was never called';
    } else if (!hasAnyHand) {
      errCode = DiagnosticErrorCodes.e201NoHand;
      errMsg ??= 'Neither hand detected in frame (0/21 landmarks)';
    }

    _hands = HandsDiagnosticData(
      status: (hasAnyHand && handDetectorErrors == 0)
          ? DiagnosticStageStatus.pass
          : DiagnosticStageStatus.fail,
      leftHandDetected: leftHandDetected,
      leftHandLandmarks: leftHandLandmarks,
      leftHandConfidence: leftHandConfidence,
      rightHandDetected: rightHandDetected,
      rightHandLandmarks: rightHandLandmarks,
      rightHandConfidence: rightHandConfidence,
      handDetectorCalls: handDetectorCalls,
      handDetectorResults: handDetectorResults,
      handDetectorErrors: handDetectorErrors,
      leftHandResults: leftHandResults,
      rightHandResults: rightHandResults,
      staticHandTestStatus: staticHandTestStatus ?? _hands.staticHandTestStatus,
      staticHandsDetected: staticHandsDetected ?? _hands.staticHandsDetected,
      staticHandLandmarks: staticHandLandmarks ?? _hands.staticHandLandmarks,
      staticHandConfidence: staticHandConfidence ?? _hands.staticHandConfidence,
      exceptionType: exceptionType,
      stackTraceSnippet: stackTraceSnippet,
      errorCode: errCode,
      errorMessage: errMsg,
    );

    if (!hasAnyHand || handDetectorErrors > 0) {
      _recordEvent(
        'HANDS',
        DiagnosticStageStatus.fail,
        errMsg ?? 'No hands detected (L: $leftHandLandmarks, R: $rightHandLandmarks)',
        errorCode: errCode,
      );
      _skipDownstreamFrom(5);
    }
    notifyListeners();
  }

  void recordStaticHandTest({
    required bool success,
    required int handsDetected,
    required int landmarksCount,
    required double confidence,
    String? errorMessage,
  }) {
    if (_isFrozen) return;

    _hands = HandsDiagnosticData(
      status: _hands.status,
      leftHandDetected: _hands.leftHandDetected,
      leftHandLandmarks: _hands.leftHandLandmarks,
      leftHandConfidence: _hands.leftHandConfidence,
      rightHandDetected: _hands.rightHandDetected,
      rightHandLandmarks: _hands.rightHandLandmarks,
      rightHandConfidence: _hands.rightHandConfidence,
      handDetectorCalls: _hands.handDetectorCalls,
      handDetectorResults: _hands.handDetectorResults,
      handDetectorErrors: _hands.handDetectorErrors,
      leftHandResults: _hands.leftHandResults,
      rightHandResults: _hands.rightHandResults,
      staticHandTestStatus: success ? DiagnosticStageStatus.pass : DiagnosticStageStatus.fail,
      staticHandsDetected: handsDetected,
      staticHandLandmarks: landmarksCount,
      staticHandConfidence: confidence,
      exceptionType: _hands.exceptionType,
      stackTraceSnippet: _hands.stackTraceSnippet,
      errorCode: _hands.errorCode,
      errorMessage: errorMessage ?? _hands.errorMessage,
    );

    _recordEvent(
      'STATIC HAND TEST',
      success ? DiagnosticStageStatus.pass : DiagnosticStageStatus.fail,
      'Hands: $handsDetected, Landmarks: $landmarksCount/21, Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
    );
    notifyListeners();
  }

  // ──────────────────────────── 4. FACE / HEAD / LIPS ────────────────────────────
  void recordFaceHeadLips({
    required bool faceDetected,
    required bool headDetected,
    required bool lipsDetected,
    required int validFacePoints,
    required int validHeadPoints,
    required int validLipPoints,
    required double confidence,
  }) {
    if (_isFrozen) return;

    final bool ok = headDetected || faceDetected;
    _faceHead = FaceHeadLipsDiagnosticData(
      status: ok ? DiagnosticStageStatus.pass : DiagnosticStageStatus.waiting,
      faceDetected: faceDetected,
      headDetected: headDetected,
      lipsDetected: lipsDetected,
      validFacePoints: validFacePoints,
      validHeadPoints: validHeadPoints,
      validLipPoints: validLipPoints,
      confidence: confidence,
    );
    notifyListeners();
  }

  // ──────────────────────────── 5. EXACT 86 KEYPOINTS ────────────────────────────
  void record86Keypoints(
    List<List<double>>? frame86, {
    int actualExtractedCount = 0,
  }) {
    if (_isFrozen) return;

    if (frame86 == null) {
      _keypoints = const Keypoints86DiagnosticData(
        status: DiagnosticStageStatus.fail,
        keypointCount: 0,
        errorCode: DiagnosticErrorCodes.e301KeypointCount,
        errorMessage: 'Keypoints frame is null',
      );
      _skipDownstreamFrom(6);
      notifyListeners();
      return;
    }

    final int count = frame86.length;
    int nanCount = 0;
    int infCount = 0;
    int zeroCount = 0;

    for (int i = 0; i < count; i++) {
      final p = frame86[i];
      if (p.length < 2) {
        nanCount++;
        continue;
      }
      final x = p[0];
      final y = p[1];

      if (x.isNaN || y.isNaN) {
        nanCount++;
      } else if (x.isInfinite || y.isInfinite) {
        infCount++;
      } else if (x.abs() < 1e-7 && y.abs() < 1e-7) {
        zeroCount++;
      }
    }

    // TASK 6: النتيجة تُحسب من actual extracted landmarks فقط وليس من مصفوفة التطبيع ذات الأصفار
    final int validCount = actualExtractedCount.clamp(0, 86);
    final bool countOk = count == 86 && validCount == 86;
    final bool valuesOk = nanCount == 0 && infCount == 0;
    final bool overallOk = countOk && valuesOk;

    String? errCode;
    String? errMsg;
    if (!countOk) {
      errCode = DiagnosticErrorCodes.e301KeypointCount;
      errMsg = 'Expected: 86 extracted, Actual extracted: $validCount/86 (Frame length: $count)';
    } else if (!valuesOk) {
      errCode = DiagnosticErrorCodes.e302InvalidKeypointValues;
      errMsg = 'Invalid coordinates detected (NaN: $nanCount, Inf: $infCount)';
    }

    final sampleP0 = count > 0 && frame86[0].length >= 2
        ? '(${frame86[0][0].toStringAsFixed(2)}, ${frame86[0][1].toStringAsFixed(2)})'
        : '(0,0)';
    final sampleP1 = count > 1 && frame86[1].length >= 2
        ? '(${frame86[1][0].toStringAsFixed(2)}, ${frame86[1][1].toStringAsFixed(2)})'
        : '(0,0)';
    final sampleP2 = count > 2 && frame86[2].length >= 2
        ? '(${frame86[2][0].toStringAsFixed(2)}, ${frame86[2][1].toStringAsFixed(2)})'
        : '(0,0)';

    _keypoints = Keypoints86DiagnosticData(
      status: overallOk
          ? DiagnosticStageStatus.pass
          : DiagnosticStageStatus.fail,
      keypointCount: count,
      validKeypoints: validCount,
      missingKeypoints: 86 - validCount,
      nanCount: nanCount,
      infinityCount: infCount,
      zeroCount: zeroCount,
      sampleP0: sampleP0,
      sampleP1: sampleP1,
      sampleP2: sampleP2,
      errorCode: errCode,
      errorMessage: errMsg,
    );

    if (!overallOk) {
      _recordEvent(
        '86 KEYPOINTS',
        DiagnosticStageStatus.fail,
        errMsg ?? 'Keypoint error',
        errorCode: errCode,
      );
      _skipDownstreamFrom(6);
    }
    notifyListeners();
  }

  // ──────────────────────────── 6. POINT GROUP DIAGNOSTICS ────────────────────────────
  void recordPointGroups({
    required int rightHandValid,
    required int leftHandValid,
    required int faceLipValid,
    required int bodyValid,
  }) {
    if (_isFrozen) return;

    final bool hasHandPoints = (rightHandValid + leftHandValid) > 0;
    final bool ok = hasHandPoints && bodyValid >= 10;
    final String? errCode = !ok
        ? DiagnosticErrorCodes.e303MappingFailure
        : null;

    _pointGroups = PointGroupDiagnosticData(
      status: ok ? DiagnosticStageStatus.pass : DiagnosticStageStatus.fail,
      rightHandValid: rightHandValid,
      rightHandTotal: 21,
      leftHandValid: leftHandValid,
      leftHandTotal: 21,
      faceLipValid: faceLipValid,
      faceLipTotal: 19,
      bodyValid: bodyValid,
      bodyTotal: 25,
      errorCode: errCode,
      errorMessage: errCode != null
          ? 'Missing required group landmarks (Hands: ${rightHandValid + leftHandValid}/42, Body: $bodyValid/25)'
          : null,
    );

    if (!ok) {
      _skipDownstreamFrom(7);
    }
    notifyListeners();
  }

  // ──────────────────────────── 7. PREPROCESSING ────────────────────────────
  void recordPreprocessing({
    required double rawMinX,
    required double rawMaxX,
    required double rawMinY,
    required double rawMaxY,
    required double normMin,
    required double normMax,
    required double normMean,
    required bool hasNan,
    required bool hasInfinity,
    required bool hasExtremeValues,
    bool isKeypointsValid = true,
  }) {
    if (_isFrozen) return;

    // TASK 7: PREPROCESSING لا يجوز أن يكون PASS إذا Keypoints غير مكتملة أو mapping غير صالح.
    if (!isKeypointsValid) {
      _preprocessing = PreprocessingDiagnosticData(
        status: DiagnosticStageStatus.skipped,
        rawMinX: rawMinX,
        rawMaxX: rawMaxX,
        rawMinY: rawMinY,
        rawMaxY: rawMaxY,
        normMin: normMin,
        normMax: normMax,
        normMean: normMean,
        hasNan: hasNan,
        hasInfinity: hasInfinity,
        hasExtremeValues: hasExtremeValues,
        errorCode: DiagnosticErrorCodes.upstreamKeypointsInvalid,
        errorMessage: 'UPSTREAM_KEYPOINTS_INVALID',
      );
      _skipDownstreamFrom(8);
      notifyListeners();
      return;
    }

    final bool ok = !hasNan && !hasInfinity && !hasExtremeValues;
    final String? errCode = hasNan
        ? DiagnosticErrorCodes.e401PreprocessingNan
        : (hasExtremeValues
              ? DiagnosticErrorCodes.e402PreprocessingRange
              : null);

    _preprocessing = PreprocessingDiagnosticData(
      status: ok ? DiagnosticStageStatus.pass : DiagnosticStageStatus.fail,
      rawMinX: rawMinX,
      rawMaxX: rawMaxX,
      rawMinY: rawMinY,
      rawMaxY: rawMaxY,
      normMin: normMin,
      normMax: normMax,
      normMean: normMean,
      hasNan: hasNan,
      hasInfinity: hasInfinity,
      hasExtremeValues: hasExtremeValues,
      errorCode: errCode,
      errorMessage: errCode != null
          ? DiagnosticErrorCodes.getDescription(errCode)
          : null,
    );

    if (!ok) {
      _recordEvent(
        'PREPROCESSING',
        DiagnosticStageStatus.fail,
        'Invalid normalized values [min: $normMin, max: $normMax]',
        errorCode: errCode,
      );
      _skipDownstreamFrom(8);
    }
    notifyListeners();
  }

  // ──────────────────────────── 8. TEMPORAL BUFFER ────────────────────────────
  void recordBuffer({
    required int currentFrames,
    required int requiredFrames,
    required int validFrames,
    required int invalidFrames,
    required int personFrames,
    required int handFrames,
    required int headFrames,
  }) {
    if (_isFrozen) return;

    final bool full = currentFrames >= requiredFrames;
    _buffer = TemporalBufferDiagnosticData(
      status: full ? DiagnosticStageStatus.pass : DiagnosticStageStatus.waiting,
      currentFrames: currentFrames,
      requiredFrames: requiredFrames,
      validFrames: validFrames,
      invalidFrames: invalidFrames,
      personFrames: personFrames,
      handFrames: handFrames,
      headFrames: headFrames,
      errorCode: !full ? DiagnosticErrorCodes.e501BufferNotReady : null,
      errorMessage: !full
          ? 'Buffer: $currentFrames / $requiredFrames frames'
          : null,
    );
    notifyListeners();
  }

  // ──────────────────────────── 9. MODEL INPUT ────────────────────────────
  void recordModelInput({
    required List<int> shape,
    required int totalValues,
    required double min,
    required double max,
    required double mean,
    required int nanCount,
    required double zeroPercentage,
  }) {
    if (_isFrozen) return;

    final bool shapeOk =
        shape.length == 4 &&
        shape[0] == 1 &&
        shape[1] == 128 &&
        shape[2] == 86 &&
        shape[3] == 2 &&
        totalValues == 22016;
    final bool valuesOk = nanCount == 0;
    final bool ok = shapeOk && valuesOk;

    final String? errCode = !ok
        ? DiagnosticErrorCodes.e602ModelInputShape
        : null;

    _modelInput = ModelInputDiagnosticData(
      status: ok ? DiagnosticStageStatus.pass : DiagnosticStageStatus.fail,
      shape: shape,
      dtype: 'float32',
      totalValues: totalValues,
      min: min,
      max: max,
      mean: mean,
      nanCount: nanCount,
      zeroPercentage: zeroPercentage,
      errorCode: errCode,
      errorMessage: errCode != null
          ? 'Input shape mismatch: expected [1, 128, 86, 2], got $shape'
          : null,
    );

    if (!ok) {
      _recordEvent(
        'MODEL INPUT',
        DiagnosticStageStatus.fail,
        'Shape mismatch or NaN input',
        errorCode: errCode,
      );
      _skipDownstreamFrom(11);
    }
    notifyListeners();
  }

  // ──────────────────────────── 10. TFLITE LOADING ────────────────────────────
  void recordTfliteLoad({
    required bool fileFound,
    required bool isLoaded,
    DiagnosticStageStatus modelFileStatus = DiagnosticStageStatus.waiting,
    int modelSizeBytes = 0,
    double modelSizeMb = 0.0,
    DiagnosticStageStatus interpreterStatus = DiagnosticStageStatus.waiting,
    DiagnosticStageStatus inputTensorStatus = DiagnosticStageStatus.waiting,
    DiagnosticStageStatus outputTensorStatus = DiagnosticStageStatus.waiting,
    DiagnosticStageStatus standaloneInferenceStatus = DiagnosticStageStatus.waiting,
    int standaloneInferenceTimeMs = 0,
    List<int>? inputShape,
    List<int>? outputShape,
    String? exceptionType,
    String? exceptionMessage,
    String? errorCode,
    String? errorMessage,
  }) {
    if (_isFrozen) return;

    final bool shapesOk =
        isLoaded &&
        listEquals(inputShape, const [1, 128, 86, 2]) &&
        listEquals(outputShape, const [1, 29, 684]);
    final bool ok = fileFound && isLoaded && shapesOk;
    final String? errCode = errorCode ?? (!ok
        ? DiagnosticErrorCodes.e601ModelNotLoaded
        : null);

    _tfliteLoad = TfliteLoadDiagnosticData(
      status: ok ? DiagnosticStageStatus.pass : DiagnosticStageStatus.fail,
      fileFound: fileFound,
      isLoaded: isLoaded,
      modelFileStatus: modelFileStatus,
      modelSizeBytes: modelSizeBytes,
      modelSizeMb: modelSizeMb,
      interpreterStatus: interpreterStatus,
      inputTensorStatus: inputTensorStatus,
      outputTensorStatus: outputTensorStatus,
      standaloneInferenceStatus: standaloneInferenceStatus,
      standaloneInferenceTimeMs: standaloneInferenceTimeMs,
      inputShape: inputShape,
      outputShape: outputShape,
      inputType: 'float32',
      outputType: 'float32',
      exceptionType: exceptionType,
      exceptionMessage: exceptionMessage,
      errorCode: errCode,
      errorMessage:
          errorMessage ??
          (!shapesOk
              ? 'Expected input: [1, 128, 86, 2], Actual input: ${inputShape ?? 'null'}\nExpected output: [1, 29, 684], Actual output: ${outputShape ?? 'null'}'
              : null),
    );

    if (ok) {
      _recordEvent(
        'TFLITE LOAD',
        DiagnosticStageStatus.pass,
        'Model loaded successfully [1,128,86,2] -> [1,29,684]',
      );
    } else {
      _recordEvent(
        'TFLITE LOAD',
        DiagnosticStageStatus.fail,
        errorMessage ?? 'TFLite load failed',
        errorCode: errCode,
      );
    }
    notifyListeners();
  }

  // ──────────────────────────── 11. INFERENCE ────────────────────────────
  void recordInferenceStart() {
    if (_isFrozen) return;
    _inference = const InferenceDiagnosticData(
      status: DiagnosticStageStatus.running,
      inferenceTimeMs: 0,
    );
    notifyListeners();
  }

  void recordInferenceSuccess(int elapsedMs) {
    if (_isFrozen) return;
    _inference = InferenceDiagnosticData(
      status: DiagnosticStageStatus.pass,
      inferenceTimeMs: elapsedMs,
    );
    _recordEvent(
      'INFERENCE',
      DiagnosticStageStatus.pass,
      'Inference executed in ${elapsedMs}ms',
    );
    notifyListeners();
  }

  void recordInferenceFailure(Object error, StackTrace stackTrace) {
    if (_isFrozen) return;
    final errType = error.runtimeType.toString();
    final errMsg = error.toString();
    final stackSnippet = stackTrace.toString().split('\n').take(3).join('\n');

    _inference = InferenceDiagnosticData(
      status: DiagnosticStageStatus.fail,
      inferenceTimeMs: 0,
      exceptionType: errType,
      exceptionMessage: errMsg,
      stackTraceSnippet: stackSnippet,
      errorCode: DiagnosticErrorCodes.e603InferenceFailed,
    );
    _recordEvent(
      'INFERENCE',
      DiagnosticStageStatus.fail,
      '$errType: $errMsg',
      errorCode: DiagnosticErrorCodes.e603InferenceFailed,
    );
    _skipDownstreamFrom(12);
    notifyListeners();
  }

  // ──────────────────────────── 12. MODEL OUTPUT VALIDATION ────────────────────────────
  void recordModelOutput({
    required List<int> outputShape,
    required int nanCount,
    required int infinityCount,
    required bool isAllZeros,
    required double min,
    required double max,
    required double mean,
  }) {
    if (_isFrozen) return;

    final bool shapeOk =
        outputShape.length == 3 &&
        outputShape[0] == 1 &&
        outputShape[1] == 29 &&
        outputShape[2] == 684;
    final bool ok =
        shapeOk && nanCount == 0 && infinityCount == 0 && !isAllZeros;
    final String? errCode = !ok
        ? DiagnosticErrorCodes.e604InvalidModelOutput
        : null;

    _modelOutput = ModelOutputDiagnosticData(
      status: ok ? DiagnosticStageStatus.pass : DiagnosticStageStatus.fail,
      outputShape: outputShape,
      nanCount: nanCount,
      infinityCount: infinityCount,
      isAllZeros: isAllZeros,
      min: min,
      max: max,
      mean: mean,
      errorCode: errCode,
      errorMessage: errCode != null
          ? 'Output validation failed (NaN: $nanCount, AllZeros: $isAllZeros)'
          : null,
    );

    if (!ok) {
      _recordEvent(
        'MODEL OUTPUT',
        DiagnosticStageStatus.fail,
        'Output tensor invalid',
        errorCode: errCode,
      );
      _skipDownstreamFrom(13);
    }
    notifyListeners();
  }

  // ──────────────────────────── 13. RAW TOP CLASSES ────────────────────────────
  void recordRawTopClasses({
    required List<TopClassItem> top5,
    required double blankRatio,
    required bool isBlankDominant,
  }) {
    if (_isFrozen) return;

    _rawTopClasses = RawTopClassesDiagnosticData(
      status: top5.isNotEmpty
          ? DiagnosticStageStatus.pass
          : DiagnosticStageStatus.waiting,
      top5: top5,
      blankRatio: blankRatio,
      isBlankDominant: isBlankDominant,
    );
    notifyListeners();
  }

  // ──────────────────────────── 14. CTC ────────────────────────────
  void recordCtc({
    required List<int> rawIds,
    required List<int> collapsedIds,
    required List<int> afterBlankRemovalIds,
    required List<String> decodedGlosses,
    required double averageConfidence,
    bool isFailed = false,
    String? errorMessage,
  }) {
    if (_isFrozen) return;

    final bool ok = !isFailed && afterBlankRemovalIds.isNotEmpty;
    final String? errCode = !ok ? DiagnosticErrorCodes.e701CtcFailed : null;

    _ctc = CtcDiagnosticData(
      status: ok ? DiagnosticStageStatus.pass : DiagnosticStageStatus.fail,
      rawIds: rawIds,
      collapsedIds: collapsedIds,
      afterBlankRemovalIds: afterBlankRemovalIds,
      decodedGlosses: decodedGlosses,
      averageConfidence: averageConfidence,
      errorCode: errCode,
      errorMessage:
          errorMessage ??
          (!ok ? 'Empty CTC sequence after blank removal' : null),
    );

    if (ok) {
      _recordEvent(
        'CTC',
        DiagnosticStageStatus.pass,
        'Decoded: $decodedGlosses (IDs: $afterBlankRemovalIds)',
      );
    } else {
      _recordEvent(
        'CTC',
        DiagnosticStageStatus.fail,
        errorMessage ?? 'CTC decoded sequence is empty',
        errorCode: errCode,
      );
      _skipDownstreamFrom(15);
    }
    notifyListeners();
  }

  // ──────────────────────────── 15. VOCABULARY ────────────────────────────
  void recordVocabulary({
    required int totalClasses,
    required bool isValid,
    required List<String> verifiedMappings,
    required List<int> invalidIds,
  }) {
    if (_isFrozen) return;

    final bool ok = isValid && totalClasses == 684 && invalidIds.isEmpty;
    final String? errCode = !ok ? DiagnosticErrorCodes.e801VocabMismatch : null;

    _vocabulary = VocabularyDiagnosticData(
      status: ok ? DiagnosticStageStatus.pass : DiagnosticStageStatus.fail,
      totalClasses: totalClasses,
      isValid: ok,
      verifiedMappings: verifiedMappings,
      invalidIds: invalidIds,
      errorCode: errCode,
      errorMessage: errCode != null
          ? 'Vocabulary verification failed (Classes: $totalClasses, Invalid: $invalidIds)'
          : null,
    );

    if (!ok) {
      _recordEvent(
        'VOCABULARY',
        DiagnosticStageStatus.fail,
        'Vocab mismatch',
        errorCode: errCode,
      );
      _skipDownstreamFrom(16);
    }
    notifyListeners();
  }

  // ──────────────────────────── 16. FINAL OUTPUT ────────────────────────────
  void recordFinalOutput({
    required String? rawModelGloss,
    required String? finalGloss,
    required bool isConfirmed,
    required String decision,
    String? rejectionReason,
  }) {
    if (_isFrozen) return;

    final bool ok = isConfirmed && finalGloss != null && finalGloss.isNotEmpty;
    _finalOutput = FinalOutputDiagnosticData(
      status: ok
          ? DiagnosticStageStatus.pass
          : (decision == 'REJECTED'
                ? DiagnosticStageStatus.fail
                : DiagnosticStageStatus.waiting),
      rawModelGloss: rawModelGloss,
      finalGloss: finalGloss,
      isConfirmed: isConfirmed,
      decision: decision,
      rejectionReason: rejectionReason,
    );

    _recordEvent(
      'FINAL OUTPUT',
      ok ? DiagnosticStageStatus.pass : DiagnosticStageStatus.fail,
      'Raw: "$rawModelGloss" -> Decision: $decision ($rejectionReason)',
    );
    notifyListeners();
  }

  // ──────────────────────────── SEQUENTIAL GATING ────────────────────────────
  void _skipDownstreamFrom(int stageIndex) {
    // لا يتم إطلاقاً مسح تشخيصات الموديل (TFLite Load / Vocabulary) أو كشف الشخص والأيدي
    // عند تعثر مرحلة إشارية، وذلك ضماناً لاستقلال المسارين A و B تماماً.
    if (stageIndex <= 8) {
      _buffer = const TemporalBufferDiagnosticData(
        status: DiagnosticStageStatus.skipped,
      );
    }
    if (stageIndex <= 9) {
      _modelInput = const ModelInputDiagnosticData(
        status: DiagnosticStageStatus.skipped,
      );
    }
    if (stageIndex <= 11) {
      _inference = const InferenceDiagnosticData(
        status: DiagnosticStageStatus.skipped,
      );
    }
    if (stageIndex <= 12) {
      _modelOutput = const ModelOutputDiagnosticData(
        status: DiagnosticStageStatus.skipped,
      );
    }
    if (stageIndex <= 13) {
      _rawTopClasses = const RawTopClassesDiagnosticData(
        status: DiagnosticStageStatus.skipped,
      );
    }
    if (stageIndex <= 14) {
      _ctc = const CtcDiagnosticData(status: DiagnosticStageStatus.skipped);
    }
    if (stageIndex <= 16) {
      _finalOutput = const FinalOutputDiagnosticData(
        status: DiagnosticStageStatus.skipped,
      );
    }
  }
}
