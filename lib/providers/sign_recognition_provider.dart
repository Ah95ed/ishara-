import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara/models/sign_segment.dart';
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
  })  : _modelService = modelService ?? IsharaRecognitionService(),
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
  List<String> get currentGlossSequence => List.unmodifiable(_currentGlossSequence);
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
      if (!vocabOk) {
        _error = 'فشل تحميل قاموس المفردات (ishara_vocab.json)';
        notifyListeners();
        return false;
      }

      final modelOk = await _modelService.loadModel();
      if (!modelOk) {
        _error = 'فشل تحميل نموذج لغة الإشارة (ishara_model.tflite)';
        notifyListeners();
        return false;
      }

      await _poseExtractor.initialize();

      _isModelLoaded = true;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _isModelLoaded = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// بدء عملية التعرف المستمر
  void startRecognition() {
    if (!_isModelLoaded) {
      _error = 'النموذج غير جاهز للبدء';
      notifyListeners();
      return;
    }
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
    if (!_isModelLoaded || !_isRecognizing) return;

    try {
      // 1. استخراج معالم الأيدي والوضعيات من الكاميرا مع دوران الإطار والمرآة
      final extracted = await _poseExtractor.extractFromCameraImage(
        image,
        sensorOrientation: sensorOrientation,
        isFrontCamera: isFrontCamera,
        deviceOrientation: deviceOrientation,
      );

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
      _lastPresence = presence;

      // 4. تطبيق المعالجة المسبقة والتطبيع الصارم المطابق لـ datasetv2.py
      final frame86x2 = _preprocessor.processFrame(
        rawRightHand: extracted.rightHand,
        rawLeftHand: extracted.leftHand,
        rawLips: extracted.lips,
        rawBody: extracted.body,
      );

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
    } catch (e) {
      debugPrint('[SignRecognitionProvider] Frame process error: $e');
    }
  }

  /// تحليل الشريحة المكتملة عبر نموذج TFLite مع التحقق المزدوج وطبقة الرفض (المتطلب 16 و 19)
  Future<void> _analyzeCompletedSegment(SignSegment segment) async {
    _isInferenceRunning = true;

    try {
      // ──────────────── نافذة A: الشريحة الكاملة مع أخذ العينات الزمنية ────────────────
      final windowA = FrameBuffer.padOrResampleTo128(segment.frames);
      final logitsA = _modelService.runInference(windowA);

      if (logitsA == null) {
        _rejectAndReset('فشل تشغيل نموذج الاستنتاج');
        return;
      }

      // تحليل Logits النافذة A وحساب Top-10 و Blank Ratio
      final analysisA = _modelService.analyzeLogits(
        logitsA,
        vocabService: _vocabService,
      );
      _lastTop10 = analysisA.top10Classes;

      // المتطلب 18: إذا كانت النتيجة يسيطر عليها الـ Blank تماماً ➔ NO_SIGN طبيعي
      if (analysisA.isBlankDominant) {
        _rejectAndReset('سيطرة Blank على التسلسل (حركة غير إشارية)');
        return;
      }

      // فك التشفير عبر CTC Decoder للنافذة A
      final decodedA = _ctcDecoder.decodeLogits(logitsA);
      if (decodedA.isEmpty) {
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
        _rejectAndReset('حرف منفرد أو رمز غير مقبول: $candidateA');
        return;
      }

      // 2. فحص الحد الأدنى لثقة التسلسل
      if (confA < 0.40) {
        _rejectAndReset('ثقة استنتاج ضعيفة: ${(confA * 100).toStringAsFixed(1)}%');
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
      final bool isTemporallyConsistent = candidateB != null &&
          (candidateA == candidateB || candidateA.contains(candidateB) || candidateB.contains(candidateA));

      if (!isTemporallyConsistent && candidateB != null && candidateB.isNotEmpty) {
        // تعارض حاد بين النافذتين ➔ UNCERTAIN
        _rejectAndReset('تعارض زمني غير مستقر بين النافذتين (A: $candidateA, B: $candidateB)');
        return;
      }

      // ──────────────── قمع التكرار اللحظي (المتطلب 28) ────────────────
      if (candidateA == _stateMachine.lastConfirmedWord) {
        _rejectAndReset('قمع تكرار نفس الكلمة السابقة دون فاصل انتقال');
        return;
      }

      // ──────────────── اعتماد الإشارة (CONFIRMED) ────────────────
      final double finalConfidence = confB > 0 ? (confA * 0.6 + confB * 0.4) : confA;
      _confirmSign(candidateA, finalConfidence);
    } catch (e) {
      debugPrint('[SignRecognitionProvider] Segment analysis error: $e');
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
