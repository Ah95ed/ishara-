import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara/models/sign_segment.dart';
import 'package:ishara/services/diagnostics/diagnostic_models.dart';
import 'package:ishara/services/diagnostics/ishara_diagnostic_service.dart';
import 'package:ishara/services/pose/person_presence_detector.dart';
import 'package:ishara/services/pose/pose_extractor_service.dart';
import 'package:ishara/services/pose/pose_preprocessor.dart';
import 'package:ishara/services/pose/sign_presence_validator.dart';
import 'package:ishara/services/pose/sign_state_machine.dart';
import 'package:ishara/services/pose/temporal_motion_analyzer.dart';
import 'package:ishara/services/tflite/ctc_greedy_decoder.dart';
import 'package:ishara/services/tflite/frame_buffer.dart';
import 'package:ishara/services/tflite/ishara_recognition_service.dart';
import 'package:ishara/services/tflite/ishara_vocab_service.dart';
import 'package:ishara/services/word_only_filter.dart';

/// مزود الحالة الرئيسي لتمييز لغة الإشارة العربية (SignRecognitionProvider)
/// ينسق بين:
/// 1. كاشف حضور الشخص واليد المركزي (PersonPresenceDetector)
/// 2. التحقق الصارم من الحضور (SignPresenceValidator)
/// 3. محلل الحركة الزمني وطاقة الحركة مع Pre-roll (TemporalMotionAnalyzer)
/// 4. آلة الحالة الزمنية لتقطيع الإشارة (SignStateMachine)
/// 5. نموذج CSLR Transformer (ishara_model.tflite) وفك تشفير CTC والتحقق المزدوج (A & B)
/// 6. طبقة الرفض وقمع التكرار
class SignRecognitionProvider extends ChangeNotifier {
  final IsharaRecognitionService _modelService;
  final IsharaVocabService _vocabService;
  final PosePreprocessor _preprocessor;
  final PoseExtractorService _poseExtractor;
  final SignPresenceValidator _presenceValidator;
  final PersonPresenceDetector _presenceDetector;
  final TemporalMotionAnalyzer _motionAnalyzer;
  final SignStateMachine _stateMachine;
  late final CtcGreedyDecoder _ctcDecoder;

  bool _isModelLoaded = false;
  bool _isRecognizing = false;
  bool _isInferenceRunning = false;
  int cameraFramesReceived = 0;
  int personDetectorCalls = 0;
  int personDetectorResults = 0;
  int personDetectorErrors = 0;
  DateTime? lastPersonDetectorCall;
  DateTime? lastPersonDetectorResult;
  String? _currentGloss;
  final List<String> _currentGlossSequence = [];
  double? _confidence;
  String? _error;

  // تشخيصات المطور ومؤشرات الوقت الحقيقي
  FramePresenceResult _lastPresence = FramePresenceResult.empty;
  TemporalMotionResult _lastMotion = TemporalMotionResult.zero;
  List<RawClassEntry> _lastTop10 = [];
  String? _lastCandidateWord;
  double _lastValidHandRatio = 0.0;
  double _lastValidHeadRatio = 0.0;
  String _rejectionReason = 'NONE';

  SignRecognitionProvider({
    IsharaRecognitionService? modelService,
    IsharaVocabService? vocabService,
    PosePreprocessor? preprocessor,
    PoseExtractorService? poseExtractor,
    SignPresenceValidator? presenceValidator,
    PersonPresenceDetector? presenceDetector,
    TemporalMotionAnalyzer? motionAnalyzer,
    SignStateMachine? stateMachine,
  }) : _modelService = modelService ?? IsharaRecognitionService(),
       _vocabService = vocabService ?? IsharaVocabService(),
       _preprocessor = preprocessor ?? PosePreprocessor(),
       _poseExtractor = poseExtractor ?? PoseExtractorService(),
       _presenceValidator = presenceValidator ?? SignPresenceValidator(),
       _presenceDetector = presenceDetector ?? PersonPresenceDetector(),
       _motionAnalyzer = motionAnalyzer ?? TemporalMotionAnalyzer(),
       _stateMachine = stateMachine ?? SignStateMachine() {
    _ctcDecoder = CtcGreedyDecoder(vocabService: _vocabService);
    _stateMachine.addListener(_onStateMachineChanged);
  }

  // ────────────────────────────────── Getters ──────────────────────────────────
  bool get isModelLoaded => _isModelLoaded;
  bool get isRecognizing => _isRecognizing;
  String? get currentGloss => _currentGloss;
  List<String> get currentGlossSequence =>
      List.unmodifiable(_currentGlossSequence);
  double? get confidence => _confidence;
  String? get error => _error;
  SignTemporalState get state => _stateMachine.state;
  bool get isAnalyzing => _stateMachine.state == SignTemporalState.analyzing;

  // Getters للمتطلب 30 (Debug Overlay)
  bool get personPresent => _presenceDetector.isPersonPresent;
  bool get bodyPosePresent => _presenceDetector.currentState.bodyPosePresent;
  bool get headPresent => _lastPresence.headPresent;
  bool get handPresent => _presenceDetector.isHandPresent;
  bool get leftHandPresent => _presenceDetector.currentState.leftHandPresent;
  bool get rightHandPresent => _presenceDetector.currentState.rightHandPresent;
  bool get facePresent => _lastPresence.facePresent;
  bool get lipsPresent => _lastPresence.lipsPresent;
  double get motionEnergy => _lastMotion.motionEnergy;
  int get activeFramesCount => _stateMachine.activeFramesCount;
  double get validHandRatio => _lastValidHandRatio;
  double get validHeadRatio => _lastValidHeadRatio;
  String? get candidateWord => _lastCandidateWord;
  List<RawClassEntry> get top10Classes => List.unmodifiable(_lastTop10);
  String get rejectionReason => _rejectionReason;

  void _onStateMachineChanged() {
    notifyListeners();
  }

  /// تهيئة النموذج والمفردات ومحرك الكشف
  Future<bool> initialize() async {
    _error = null;
    notifyListeners();

    try {
      final vocabOk = await _vocabService.loadVocab();
      final verifiedMappings = <String>[];
      final invalidIds = <int>[];
      for (int i = 1; i < min(10, _vocabService.vocabSize); i++) {
        final g = _vocabService.getGloss(i);
        if (g != null) {
          verifiedMappings.add('ID $i -> "$g"');
        } else {
          invalidIds.add(i);
        }
      }
      IsharaDiagnosticService().recordVocabulary(
        totalClasses: _vocabService.vocabSize,
        isValid: vocabOk,
        verifiedMappings: verifiedMappings,
        invalidIds: invalidIds,
      );

      await _poseExtractor.initialize();

      final modelOk = await _modelService.loadModel();
      IsharaDiagnosticService().recordTfliteLoad(
        fileFound: true,
        isLoaded: modelOk,
        inputShape: _modelService.inputShape,
        outputShape: _modelService.outputShape,
      );

      _isModelLoaded = modelOk;
      _error = modelOk
          ? null
          : 'فشل تحميل نموذج لغة الإشارة (ishara_model.tflite)';
      notifyListeners();
      return modelOk && vocabOk;
    } catch (e) {
      _isModelLoaded = false;
      _error = e.toString();
      IsharaDiagnosticService().recordTfliteLoad(
        fileFound: false,
        isLoaded: false,
        errorMessage: e.toString(),
      );
      notifyListeners();
      return false;
    }
  }

  /// تشغيل فحص وتشخيص نموذج لغة الإشارة المستقل (PATH A)
  Future<ModelDiagnosticResult> runModelDiagnostics() async {
    final result = await _modelService.runModelDiagnostics();
    _isModelLoaded = _modelService.isLoaded;
    notifyListeners();
    return result;
  }

  /// تشغيل الفحص الإلزامي لصورة اليد الثابتة (TASK 4 - Static Image Hand Test)
  Future<StaticHandTestResult> runStaticHandTest() async {
    final result = await _poseExtractor.runStaticHandTest();
    IsharaDiagnosticService().recordStaticHandTest(
      success: result.success,
      handsDetected: result.handsDetected,
      landmarksCount: result.landmarksCount,
      confidence: result.confidence,
      errorMessage: result.errorMessage,
    );
    notifyListeners();
    return result;
  }

  /// بدء عملية التعرف المستمر
  void startRecognition() {
    _isRecognizing = true;
    _presenceDetector.reset();
    _stateMachine.reset();
    _motionAnalyzer.reset();
    _preprocessor.reset();
    _presenceValidator.reset();
    _currentGloss = null;
    _currentGlossSequence.clear();
    _confidence = null;
    _error = null;
    _lastCandidateWord = null;
    _rejectionReason = 'NONE';
    notifyListeners();
  }

  /// إيقاف التعرف مؤقتاً
  void stopRecognition() {
    _isRecognizing = false;
    _presenceDetector.reset();
    _stateMachine.reset();
    _motionAnalyzer.reset();
    _preprocessor.reset();
    _presenceValidator.reset();
    notifyListeners();
  }

  /// معالجة إطار الكاميرا الوارد (Camera Frame Pipeline)
  Future<void> processFrame(
    CameraImage image, {
    int? sensorOrientation,
    bool isFrontCamera = false,
    DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp,
  }) async {
    if (!_isRecognizing) return;

    cameraFramesReceived++;

    try {
      if (!_poseExtractor.isInitialized) {
        await _poseExtractor.initialize();
      }

      personDetectorCalls++;
      lastPersonDetectorCall = DateTime.now();

      // 1. استخراج معالم الأيدي والوضعيات من الكاميرا مع دوران الإطار والمرآة
      final extracted = await _poseExtractor.extractFromCameraImage(
        image,
        sensorOrientation: sensorOrientation,
        isFrontCamera: isFrontCamera,
        deviceOrientation: deviceOrientation,
      );

      personDetectorResults++;
      lastPersonDetectorResult = DateTime.now();

      // 2. تحديث كاشف حضور الشخص واليد المركزي مع الاستقرار الزمني (Temporal Persistence)
      final presenceState = _presenceDetector.updatePresence(
        bodyPosePresent: extracted.bodyPosePresent,
        headPresent: extracted.headPresent,
        facePresent: extracted.facePresent,
        lipsPresent: extracted.lipsPresent,
        leftHandPresent: extracted.leftHand != null,
        rightHandPresent: extracted.rightHand != null,
      );

      // 3. تقييم الحضور الصارم
      final presence = _presenceValidator.evaluatePresence(
        rightHand: extracted.rightHand,
        leftHand: extracted.leftHand,
        lips: extracted.lips,
        body: extracted.body,
        rightHandConfidence: extracted.rightHandConfidence,
        leftHandConfidence: extracted.leftHandConfidence,
        headConfidence: extracted.headConfidence,
        bodyPosePresent: presenceState.bodyPosePresent,
        headPresentDirect: presenceState.headPresent,
        facePresentDirect: presenceState.facePresent,
        personPresentDirect: presenceState.personPresent,
      );
      // 4. تطبيق المعالجة المسبقة والتطبيع الصارم المطابق لـ datasetv2.py
      final frame86x2 = _preprocessor.processFrame(
        rawRightHand: extracted.rightHand,
        rawLeftHand: extracted.leftHand,
        rawLips: extracted.lips,
        rawBody: extracted.body,
      );

      // تسجيل تشخيصات الإطار للمراحل 1..8 بالكامل وبشكل مستقل تماماً عن الموديل
      _recordDiagnosticsForFrame(
        extracted,
        presenceState,
        frame86x2,
        image: image,
        sensorOrientation: sensorOrientation,
        isFrontCamera: isFrontCamera,
        deviceOrientation: deviceOrientation,
      );

      // إشعار المستمعين لتحديث الشاشة وواجهة الكشف
      notifyListeners();

      // مسار التعرف على الإشارة مشروط بجاهزية الموديل وحضور الشخص
      if (!_isModelLoaded || !_vocabService.isLoaded) {
        return;
      }

      if (!presence.personPresent) {
        return;
      }

      // 5. تحليل الحركة الزمنية وحساب طاقة الحركة الموزونة
      final motion = _motionAnalyzer.analyzeFrame(
        rightHand: extracted.rightHand,
        leftHand: extracted.leftHand,
        lips: extracted.lips,
        body: extracted.body,
      );
      _lastMotion = motion;

      // 6. حفظ إطارات الـ Pre-roll أثناء حالة الاستعداد (READY أو COOLDOWN)
      if (presence.isSignEligible &&
          (_stateMachine.state == SignTemporalState.ready ||
              _stateMachine.state == SignTemporalState.cooldown)) {
        _motionAnalyzer.recordPreRollFrame(frame86x2);
      }

      // 7. تشغيل آلة الحالة الزمنية
      final stateBefore = _stateMachine.state;
      _stateMachine.processFrame(
        presence: presence,
        motion: motion,
        frame86x2: frame86x2,
        preRollFrames: _motionAnalyzer.preRollFrames,
      );

      // 8. طباعة سجلات الـ Debug المطلوبة بالصيغة المحددة تماماً
      _presenceDetector.logDebugInfo(_stateMachine.state);

      // 9. إذا انتقلت الحالة إلى ANALYZING ➔ تشغيل الاستنتاج وتحليل الشريحة المكتملة
      if (_stateMachine.state == SignTemporalState.analyzing &&
          stateBefore != SignTemporalState.analyzing) {
        final segment = _stateMachine.completedSegment;
        if (segment != null && !_isInferenceRunning) {
          _lastValidHandRatio = segment.validHandRatio;
          _lastValidHeadRatio = segment.validHeadRatio;
          _analyzeCompletedSegment(segment);
        }
      }
    } catch (e, stack) {
      personDetectorErrors++;
      debugPrint('PERSON DETECTOR ERROR: $e');
      debugPrint(stack.toString());
      notifyListeners();
    }
  }

  /// تحليل الشريحة المكتملة عبر نموذج TFLite مع التحقق المزدوج وطبقة الرفض (المتطلب 16 و 19)
  Future<void> _analyzeCompletedSegment(SignSegment segment) async {
    _isInferenceRunning = true;

    try {
      // ──────────────── نافذة A: الشريحة الكاملة مع أخذ العينات الزمنية ────────────────
      final windowA = FrameBuffer.padOrResampleTo128(segment.frames);

      // تسجيل تشخيص دخل النموذج STAGE 9
      _recordModelInputDiagnostics(windowA);

      final sw = Stopwatch()..start();
      IsharaDiagnosticService().recordInferenceStart();
      final logitsA = _modelService.runInference(windowA);
      sw.stop();

      if (logitsA == null) {
        IsharaDiagnosticService().recordInferenceFailure(
          StateError('TFLite runInference returned null logits'),
          StackTrace.current,
        );
        IsharaDiagnosticService().recordFinalOutput(
          rawModelGloss: '',
          finalGloss: null,
          isConfirmed: false,
          decision: 'REJECTED',
          rejectionReason:
              'فشل تشغيل نموذج الاستنتاج (TFLite Inference Failed)',
        );
        _rejectAndReset('فشل تشغيل نموذج الاستنتاج');
        return;
      }
      IsharaDiagnosticService().recordInferenceSuccess(sw.elapsedMilliseconds);

      // تسجيل تشخيص خرج النموذج STAGE 12
      _recordModelOutputDiagnostics(logitsA);

      // تحليل Logits النافذة A وحساب Top-10 و Blank Ratio
      final analysisA = _modelService.analyzeLogits(
        logitsA,
        vocabService: _vocabService,
      );
      _lastTop10 = analysisA.top10Classes;

      // تسجيل تشخيص STAGE 13: RAW TOP CLASSES
      final top5Items = <TopClassItem>[];
      for (int i = 0; i < min(5, analysisA.top10Classes.length); i++) {
        final c = analysisA.top10Classes[i];
        top5Items.add(
          TopClassItem(
            rank: i + 1,
            classId: c.classId,
            gloss: c.gloss,
            score: c.score,
          ),
        );
      }
      IsharaDiagnosticService().recordRawTopClasses(
        top5: top5Items,
        blankRatio: analysisA.blankRatio,
        isBlankDominant: analysisA.isBlankDominant,
      );

      // فك التشفير عبر CTC Decoder للنافذة A
      final decodedA = _ctcDecoder.decodeLogits(logitsA);

      // تسجيل تشخيص STAGE 14: CTC
      IsharaDiagnosticService().recordCtc(
        rawIds: decodedA.rawIds,
        collapsedIds: decodedA.collapsedIds,
        afterBlankRemovalIds: decodedA.glossIds,
        decodedGlosses: decodedA.glosses,
        averageConfidence: decodedA.averageConfidence,
        isFailed: decodedA.isEmpty,
        errorMessage: decodedA.isEmpty ? 'تسلسل CTC فارغ' : null,
      );

      // المتطلب 18: إذا كانت النتيجة يسيطر عليها الـ Blank تماماً ➔ NO_SIGN طبيعي
      if (analysisA.isBlankDominant) {
        final topGloss = top5Items.isNotEmpty ? top5Items.first.gloss : 'BLANK';
        IsharaDiagnosticService().recordFinalOutput(
          rawModelGloss: topGloss,
          finalGloss: null,
          isConfirmed: false,
          decision: 'REJECTED',
          rejectionReason: 'سيطرة Blank على التسلسل (حركة غير إشارية)',
        );
        _rejectAndReset('سيطرة Blank على التسلسل (حركة غير إشارية)');
        return;
      }

      if (decodedA.isEmpty) {
        final topGloss = top5Items.isNotEmpty ? top5Items.first.gloss : 'NONE';
        IsharaDiagnosticService().recordFinalOutput(
          rawModelGloss: topGloss,
          finalGloss: null,
          isConfirmed: false,
          decision: 'REJECTED',
          rejectionReason: 'تسلسل CTC فارغ بعد إزالة الفراغات',
        );
        _rejectAndReset('تسلسل CTC فارغ');
        return;
      }

      final candidateA = decodedA.glosses.join(' ').trim();
      final double confA = decodedA.averageConfidence;
      _lastCandidateWord = candidateA;
      _stateMachine.markCandidate(candidateA, confA);

      // ──────────────── طبقة الرفض المبدئي (Rejection Layer) ────────────────
      // 1. تصفية الحروف المنفردة (المتطلب 10 و 17)
      if (!WordOnlyFilter.isValidWord(candidateA)) {
        IsharaDiagnosticService().recordFinalOutput(
          rawModelGloss: candidateA,
          finalGloss: null,
          isConfirmed: false,
          decision: 'REJECTED',
          rejectionReason: 'حرف منفرد أو رمز غير مقبول: $candidateA',
        );
        _rejectAndReset('حرف منفرد أو رمز غير مقبول: $candidateA');
        return;
      }

      // 2. فحص الحد الأدنى لثقة التسلسل
      if (confA < 0.40) {
        IsharaDiagnosticService().recordFinalOutput(
          rawModelGloss: candidateA,
          finalGloss: null,
          isConfirmed: false,
          decision: 'REJECTED',
          rejectionReason:
              'ثقة استنتاج ضعيفة: ${(confA * 100).toStringAsFixed(1)}%',
        );
        _rejectAndReset(
          'ثقة استنتاج ضعيفة: ${(confA * 100).toStringAsFixed(1)}%',
        );
        return;
      }

      // ──────────────── نافذة B: النافذة المتداخلة للتحقق الزمني المزدوج (المتطلب 16) ────────────────
      final windowB = FrameBuffer.generateShiftedContextWindow(segment.frames);
      final logitsB = _modelService.runInference(windowB);

      String? candidateB;
      double confB = 0.0;
      if (logitsB != null) {
        final decodedB = _ctcDecoder.decodeLogits(logitsB);
        if (decodedB.isNotEmpty) {
          candidateB = decodedB.glosses.join(' ').trim();
          confB = decodedB.averageConfidence;
        }
      }

      // التحقق من توافق Candidate A و Candidate B
      final bool isTemporallyConsistent =
          candidateB != null &&
          (candidateA == candidateB ||
              candidateA.contains(candidateB) ||
              candidateB.contains(candidateA));

      if (!isTemporallyConsistent &&
          candidateB != null &&
          candidateB.isNotEmpty) {
        // تعارض حاد بين النافذتين ➔ UNCERTAIN
        IsharaDiagnosticService().recordFinalOutput(
          rawModelGloss: candidateA,
          finalGloss: null,
          isConfirmed: false,
          decision: 'REJECTED',
          rejectionReason:
              'تعارض زمني غير مستقر بين النافذتين (A: $candidateA, B: $candidateB)',
        );
        _rejectAndReset(
          'تعارض زمني غير مستقر بين النافذتين (A: $candidateA, B: $candidateB)',
        );
        return;
      }

      // ──────────────── قمع التكرار اللحظي (المتطلب 28) ────────────────
      if (candidateA == _stateMachine.lastConfirmedWord) {
        IsharaDiagnosticService().recordFinalOutput(
          rawModelGloss: candidateA,
          finalGloss: null,
          isConfirmed: false,
          decision: 'REJECTED',
          rejectionReason: 'قمع تكرار نفس الكلمة السابقة دون فاصل انتقال',
        );
        _rejectAndReset('قمع تكرار نفس الكلمة السابقة دون فاصل انتقال');
        return;
      }

      // ──────────────── اعتماد الإشارة (CONFIRMED) ────────────────
      final double finalConfidence = confB > 0
          ? (confA * 0.6 + confB * 0.4)
          : confA;
      IsharaDiagnosticService().recordFinalOutput(
        rawModelGloss: candidateA,
        finalGloss: candidateA,
        isConfirmed: true,
        decision: 'CONFIRMED',
      );
      _confirmSign(candidateA, finalConfidence);
    } catch (e) {
      debugPrint('[SignRecognitionProvider] Segment analysis error: $e');
      IsharaDiagnosticService().recordFinalOutput(
        rawModelGloss: _lastCandidateWord,
        finalGloss: null,
        isConfirmed: false,
        decision: 'REJECTED',
        rejectionReason: 'خطأ أثناء التحليل: $e',
      );
      _rejectAndReset('خطأ أثناء التحليل: $e');
    } finally {
      _isInferenceRunning = false;
    }
  }

  /// اعتماد الإشارة المؤكدة وتحديث الواجهة
  void _confirmSign(String word, double finalConfidence) {
    _currentGloss = word;
    _confidence = finalConfidence;
    _currentGlossSequence.add(word);
    _rejectionReason = 'NONE';
    _stateMachine.confirmSign(word);

    // بدء فترة التهدئة لمنع التكرار الفوري
    Future.delayed(const Duration(milliseconds: 600), () {
      if (_stateMachine.state == SignTemporalState.confirmed) {
        _stateMachine.startCooldown();
      }
    });

    notifyListeners();
  }

  /// رفض المرشح والعودة لحالة الاستعداد
  void _rejectAndReset(String reason) {
    _rejectionReason = reason;
    if (kDebugMode) {
      debugPrint('[SignRecognitionProvider] ⚠️ Rejected: $reason');
    }
    _stateMachine.startCooldown();
    notifyListeners();
  }

  // ──────────────────────────── Diagnostic Helper Methods ────────────────────────────
  void _recordDiagnosticsForFrame(
    ExtractedPoseFrame extracted,
    PersonPresenceState presenceState,
    List<List<double>> frame86x2, {
    required CameraImage image,
    int? sensorOrientation,
    bool isFrontCamera = false,
    DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp,
  }) {
    final diag = IsharaDiagnosticService();

    final int previewRotation = sensorOrientation ?? 90;
    final int deviceAngle = switch (deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    final int detectorInputRotation = isFrontCamera
        ? (previewRotation + deviceAngle) % 360
        : (previewRotation - deviceAngle + 360) % 360;

    // 1. Camera Section Diagnostic
    diag.recordCamera(
      isInitialized: true,
      isStreaming: true,
      fps: 15.0,
      frameAgeMs: 0,
      width: image.width,
      height: image.height,
      format: image.format.group.name,
      rotation: previewRotation,
      previewRotation: previewRotation,
      detectorInputRotation: detectorInputRotation,
      framesReceived: cameraFramesReceived,
      imageConversionStatus: DiagnosticStageStatus.pass,
      personDetectorCalls: personDetectorCalls,
      personDetectorResults: personDetectorResults,
      personDetectorErrors: personDetectorErrors,
      poseLandmarks: extracted.body?.length ?? (presenceState.bodyPosePresent ? 25 : 0),
      faceLandmarks: extracted.facePresent ? 11 : 0,
      leftHandLandmarks: extracted.leftHand?.length ?? 0,
      rightHandLandmarks: extracted.rightHand?.length ?? 0,
    );

    // 2. Person Detection
    diag.recordPerson(
      personPresent: presenceState.personPresent,
      posePresent: presenceState.bodyPosePresent,
      facePresent: presenceState.facePresent,
      headPresent: presenceState.headPresent,
      poseLandmarks: extracted.body?.length ?? (presenceState.bodyPosePresent ? 25 : 0),
      faceLandmarks: extracted.facePresent ? 11 : 0,
      leftHandLandmarks: extracted.leftHand?.length ?? 0,
      rightHandLandmarks: extracted.rightHand?.length ?? 0,
    );

    // 3. Hands Detection
    diag.recordHands(
      leftHandDetected: extracted.leftHand != null,
      leftHandLandmarks: extracted.leftHand?.length ?? 0,
      leftHandConfidence: extracted.leftHandConfidence,
      rightHandDetected: extracted.rightHand != null,
      rightHandLandmarks: extracted.rightHand?.length ?? 0,
      rightHandConfidence: extracted.rightHandConfidence,
      handDetectorCalls: extracted.handDetectorCalls,
      handDetectorResults: extracted.handDetectorResults,
      handDetectorErrors: extracted.handDetectorErrors,
      leftHandResults: extracted.leftHandResults,
      rightHandResults: extracted.rightHandResults,
      exceptionType: extracted.handDetectorException != null ? 'HandDetectorException' : null,
      stackTraceSnippet: extracted.handDetectorStackTrace,
      errorMessage: extracted.handDetectorException,
    );

    // 4. Face/Head/Lips
    diag.recordFaceHeadLips(
      faceDetected: extracted.facePresent,
      headDetected: extracted.headPresent,
      lipsDetected: extracted.lipsPresent,
      validFacePoints: extracted.facePresent ? 11 : 0,
      validHeadPoints: extracted.body?.length ?? 0,
      validLipPoints: extracted.lips?.length ?? 0,
      confidence: extracted.headConfidence,
    );

    final int actualBodyPoints = extracted.body?.length ?? 0;
    final int actualLipPoints = extracted.lips?.length ?? 0;
    final int actualLeftHandPoints = extracted.leftHand?.length ?? 0;
    final int actualRightHandPoints = extracted.rightHand?.length ?? 0;
    final int actualExtractedKeypoints = actualBodyPoints +
        actualLipPoints +
        actualLeftHandPoints +
        actualRightHandPoints;

    // 5. 86 Keypoints
    diag.record86Keypoints(
      frame86x2,
      actualExtractedCount: actualExtractedKeypoints,
    );

    // 6. Point Groups
    diag.recordPointGroups(
      rightHandValid: actualRightHandPoints,
      leftHandValid: actualLeftHandPoints,
      faceLipValid: actualLipPoints,
      bodyValid: actualBodyPoints,
    );

    // 7. Preprocessing
    double rawMinX = double.infinity, rawMaxX = double.negativeInfinity;
    double rawMinY = double.infinity, rawMaxY = double.negativeInfinity;
    void checkPoints(List<List<double>>? pts) {
      if (pts == null) return;
      for (final p in pts) {
        if (p.length >= 2) {
          if (p[0] < rawMinX) rawMinX = p[0];
          if (p[0] > rawMaxX) rawMaxX = p[0];
          if (p[1] < rawMinY) rawMinY = p[1];
          if (p[1] > rawMaxY) rawMaxY = p[1];
        }
      }
    }

    checkPoints(extracted.rightHand);
    checkPoints(extracted.leftHand);
    checkPoints(extracted.lips);
    checkPoints(extracted.body);
    if (rawMinX == double.infinity) rawMinX = 0.0;
    if (rawMaxX == double.negativeInfinity) rawMaxX = 0.0;
    if (rawMinY == double.infinity) rawMinY = 0.0;
    if (rawMaxY == double.negativeInfinity) rawMaxY = 0.0;

    double normMin = double.infinity,
        normMax = double.negativeInfinity,
        normSum = 0.0;
    bool hasNan = false, hasInf = false, hasExtreme = false;
    int totalNorm = 0;
    for (final p in frame86x2) {
      for (final v in p) {
        if (v.isNaN) hasNan = true;
        if (v.isInfinite) hasInf = true;
        if (v.abs() > 3.0) hasExtreme = true;
        if (v < normMin) normMin = v;
        if (v > normMax) normMax = v;
        normSum += v;
        totalNorm++;
      }
    }
    final normMean = totalNorm > 0 ? normSum / totalNorm : 0.0;
    if (normMin == double.infinity) normMin = 0.0;
    if (normMax == double.negativeInfinity) normMax = 0.0;

    // TASK 7: Preprocessing لا يكون PASS إذا كانت Keypoints غير مكتملة (أقل من 86)
    final bool isKeypointsValid = actualExtractedKeypoints == 86;

    diag.recordPreprocessing(
      rawMinX: rawMinX,
      rawMaxX: rawMaxX,
      rawMinY: rawMinY,
      rawMaxY: rawMaxY,
      normMin: normMin,
      normMax: normMax,
      normMean: normMean,
      hasNan: hasNan,
      hasInfinity: hasInf,
      hasExtremeValues: hasExtreme,
      isKeypointsValid: isKeypointsValid,
    );

    // 8. Buffer
    diag.recordBuffer(
      currentFrames: _stateMachine.activeFramesCount,
      requiredFrames: 128,
      validFrames: _stateMachine.activeFramesCount,
      invalidFrames: 0,
      personFrames: presenceState.personPresent
          ? _stateMachine.activeFramesCount
          : 0,
      handFrames: (extracted.rightHand != null || extracted.leftHand != null)
          ? _stateMachine.activeFramesCount
          : 0,
      headFrames: extracted.headPresent ? _stateMachine.activeFramesCount : 0,
    );
  }

  void _recordModelInputDiagnostics(List<List<List<double>>> windowA) {
    double inMin = double.infinity,
        inMax = double.negativeInfinity,
        inSum = 0.0;
    int inNan = 0, inZeros = 0, inCount = 0;
    for (final frame in windowA) {
      for (final pt in frame) {
        for (final val in pt) {
          inCount++;
          if (val.isNaN) inNan++;
          if (val.abs() < 1e-7) inZeros++;
          if (val < inMin) inMin = val;
          if (val > inMax) inMax = val;
          inSum += val;
        }
      }
    }
    final inMean = inCount > 0 ? inSum / inCount : 0.0;
    if (inMin == double.infinity) inMin = 0.0;
    if (inMax == double.negativeInfinity) inMax = 0.0;
    final zeroPct = inCount > 0 ? (inZeros / inCount) * 100.0 : 0.0;

    IsharaDiagnosticService().recordModelInput(
      shape: [1, windowA.length, windowA.isNotEmpty ? windowA[0].length : 0, 2],
      totalValues: inCount,
      min: inMin,
      max: inMax,
      mean: inMean,
      nanCount: inNan,
      zeroPercentage: zeroPct,
    );
  }

  void _recordModelOutputDiagnostics(List<List<double>> logitsA) {
    int outNan = 0, outInf = 0, outZeros = 0, outCount = 0;
    double outMin = double.infinity,
        outMax = double.negativeInfinity,
        outSum = 0.0;
    for (final step in logitsA) {
      for (final v in step) {
        outCount++;
        if (v.isNaN) outNan++;
        if (v.isInfinite) outInf++;
        if (v.abs() < 1e-7) outZeros++;
        if (v < outMin) outMin = v;
        if (v > outMax) outMax = v;
        outSum += v;
      }
    }
    final outMean = outCount > 0 ? outSum / outCount : 0.0;
    if (outMin == double.infinity) outMin = 0.0;
    if (outMax == double.negativeInfinity) outMax = 0.0;

    IsharaDiagnosticService().recordModelOutput(
      outputShape: [
        1,
        logitsA.length,
        logitsA.isNotEmpty ? logitsA[0].length : 0,
      ],
      nanCount: outNan,
      infinityCount: outInf,
      isAllZeros: outZeros == outCount,
      min: outMin,
      max: outMax,
      mean: outMean,
    );
  }

  /// مسح التسلسل وسجل التنبؤات
  void clearPrediction() {
    _currentGloss = null;
    _currentGlossSequence.clear();
    _confidence = null;
    _lastCandidateWord = null;
    _lastTop10.clear();
    _rejectionReason = 'NONE';
    _stateMachine.reset();
    _motionAnalyzer.reset();
    _preprocessor.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _stateMachine.removeListener(_onStateMachineChanged);
    stopRecognition();
    _modelService.dispose();
    _poseExtractor.dispose();
    _vocabService.clear();
    _stateMachine.dispose();
    super.dispose();
  }
}
