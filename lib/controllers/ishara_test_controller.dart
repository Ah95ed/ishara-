import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara/ml/ctc/ishara_ctc_decoder.dart';
import 'package:ishara/models/ishara_recognition_test_session.dart';
import 'package:ishara/services/vision_detection_service.dart';

/// IsharaTestController
/// متحكم دورة حياة تجربة الاختبار البسيطة والمباشرة لـ Ishara:
/// 1. IDLE: الحالة: جاهز -> زر [ ابدأ الاختبار ]
/// 2. COLLECTING: جاري الالتقاط... مع شريط تقدم (0..128) وزمن أمان 15 ثانية
/// 3. PROCESSING: جاري التحليل... (استنتاج TFLite واحد + CTC + Vocab)
/// 4. RESULT: النتيجة: بنت - اخ - صغير -> زر [ نسخ النتيجة ] وزر [ اختبار جديد ]
/// 5. FAILED: لم تكتمل البيانات، أعد المحاولة -> زر [ اختبار جديد ]
class IsharaTestController extends ChangeNotifier {
  final VisionDetectionService _visionService;

  RecognitionTestState _state = RecognitionTestState.idle;
  int _collectedFrames = 0;
  int? _startSequenceId;
  DateTime? _sessionStartTime;
  Timer? _safetyTimeoutTimer;
  bool _isExecuting = false;

  IsharaRecognitionTestSession? _session;
  String _displayResult = '';
  String? _errorMessage;

  IsharaTestController(this._visionService);

  // ── Getters ──
  RecognitionTestState get state => _state;
  bool get isIdle => _state.isIdle;
  bool get isCollecting => _state.isCollecting;
  bool get isProcessing => _state.isProcessing;
  bool get isResult => _state.isResult;
  bool get isFailed => _state.isFailed;

  int get collectedFrames => _collectedFrames;
  int get targetFrames => 128;
  double get progressFraction => (_collectedFrames / targetFrames).clamp(0.0, 1.0);
  String get displayResult => _displayResult;
  IsharaRecognitionTestSession? get session => _session;
  String? get errorMessage => _errorMessage;

  bool get canStartTest => _state.isIdle && !_isExecuting;

  /// بدء جلسة اختبار جديدة من نقطة الصفر
  void startSimpleTest() {
    if (!canStartTest) return;

    _errorMessage = null;
    _displayResult = '';
    _session = null;
    _collectedFrames = 0;
    _isExecuting = false;
    _sessionStartTime = DateTime.now();

    // التقاط معرف آخر إطار حالي لبدء العد الجديد من لحظة الضغط تماماً
    final latestId =
        _visionService.ringBuffer.getStatus().latestFrameSequenceId ?? 0;
    _startSequenceId = latestId;

    _state = RecognitionTestState.collecting;
    notifyListeners();

    // بدء مؤقت الأمان (15 ثانية كحد أقصى)
    _safetyTimeoutTimer?.cancel();
    _safetyTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (_state == RecognitionTestState.collecting) {
        _onSafetyTimeout();
      }
    });
  }

  /// يتم استدعاؤها مع كل إطار كاميرا تتم معالجته
  void onFrameProcessed(int latestSequenceId) {
    if (_state != RecognitionTestState.collecting) return;
    if (_startSequenceId == null) return;

    final count = (latestSequenceId - _startSequenceId!).clamp(0, targetFrames);
    _collectedFrames = count;
    notifyListeners();

    // عند اكتمال الـ 128 إطاراً جديدة: نتوقف فوراً ونحلل
    if (count >= targetFrames && !_isExecuting) {
      _safetyTimeoutTimer?.cancel();
      _onCollectionCompleted();
    }
  }

  /// انتهاء مهلة الأمان (15 ثانية) قبل اكتمال الـ 128 إطاراً
  void _onSafetyTimeout() {
    final duration = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inMilliseconds
        : 15000;

    _visionService.continuousSignService.activityDetector
        .forceFinalizeSignActivity(reason: 'TIMEOUT');

    _state = RecognitionTestState.failed;
    _displayResult = 'لم تكتمل البيانات، أعد المحاولة';
    _errorMessage = 'انتهت مهلة الـ 15 ثانية قبل اكتمال 128 إطاراً';
    _session = IsharaRecognitionTestSession.failed(
      collectedFrames: _collectedFrames,
      durationMs: duration,
      reason: 'TIMEOUT',
      errorMessage: _displayResult,
    );
    notifyListeners();
  }

  /// اكتمال جمع 128 إطاراً وبدء الاستنتاج النهائي الفردي
  Future<void> _onCollectionCompleted() async {
    _isExecuting = true;
    _state = RecognitionTestState.processing;
    _displayResult = 'جاري التحليل...';
    notifyListeners();

    try {
      final startTime = _sessionStartTime ?? DateTime.now();
      final inferenceStart = DateTime.now();

      // إغلاق أي مقطع نشاط مفتوح كإجراء أمان
      _visionService.continuousSignService.activityDetector
          .forceFinalizeSignActivity(reason: 'FRAME_LIMIT');

      // 1. أخذ لقطة عميقة غير قابلة للتعديل لآخر 128 إطاراً
      final inputSequence =
          _visionService.ringBuffer.buildModelInput(applyHandsBackwardFill: true);
      if (inputSequence == null) {
        _state = RecognitionTestState.failed;
        _displayResult = 'تعذر استخراج بيانات الإطارات';
        _isExecuting = false;
        notifyListeners();
        return;
      }

      // 2. تحليل جودة التسلسل في الخلفية
      final quality =
          _visionService.ringBuffer.analyzeCurrentSequence(captureTime: DateTime.now());

      // 3. تشغيل موديل TFLite مرة واحدة فقط
      final rawOutput =
          await _visionService.tfliteService.runRealSequenceInference(inputSequence);
      final inferenceTimeMs =
          DateTime.now().difference(inferenceStart).inMilliseconds;
      final totalDurationMs =
          DateTime.now().difference(startTime).inMilliseconds;

      if (!rawOutput.isSuccess) {
        _state = RecognitionTestState.failed;
        _displayResult = 'فشل معالجة الموديل';
        _errorMessage = rawOutput.errorMessage;
        _isExecuting = false;
        notifyListeners();
        return;
      }

      // 4. تطبيق Greedy CTC Decode الصارم
      final ctcResult = IsharaCtcDecoder.decodeRawArgmax(rawOutput.rawArgmax);

      // 5. ربط المفردات الرسمية
      final glosses =
          _visionService.vocabService.mapIdsToGlosses(ctcResult.decodedIds);

      // 6. التحقق من الجودة والنتائج الفارغة وفق الشروط
      String finalDisplay;
      if (quality.rawCoveragePercent < 60.0) {
        // جودة منخفضة جداً (البند 11)
        finalDisplay = 'الإشارة غير واضحة، أعد المحاولة';
      } else if (ctcResult.decodedIds.isEmpty) {
        // نتيجة CTC فارغة (البند 10)
        finalDisplay = 'لم يتم التعرف على إشارة واضحة';
      } else {
        // عرض الكلمات المستخرجة فقط (البند 5)
        finalDisplay = glosses.join(' - ');
      }

      // 7. بناء التقرير المخفي للحافظة
      final actDetector = _visionService.continuousSignService.activityDetector;
      _session = IsharaRecognitionTestSession(
        capturedAt: DateTime.now(),
        collectedFrames: targetFrames,
        targetFrames: targetFrames,
        durationMs: totalDurationMs,
        sequenceQualityPct: quality.rawCoveragePercent,
        imputationPct: quality.imputationPercent,
        rhCoveragePct: quality.rhCoveragePercent,
        lhCoveragePct: quality.lhCoveragePercent,
        lipsCoveragePct: quality.lipsCoveragePercent,
        bodyCoveragePct: quality.bodyCoveragePercent,
        inputShape: inputSequence.shape,
        outputShape: rawOutput.outputShape,
        inferencePass: true,
        inferenceTimeMs: inferenceTimeMs,
        rawArgmaxIds: rawOutput.rawArgmax,
        ctcIds: ctcResult.decodedIds,
        glosses: glosses,
        finalResultDisplay: finalDisplay,
        signStartDetected: actDetector.signStartTime != null,
        signEndDetected: actDetector.signEndTime != null,
        endReason: actDetector.endReason.isNotEmpty ? actDetector.endReason : 'FRAME_LIMIT',
        errors: 'NONE',
      );

      _displayResult = finalDisplay;
      _state = RecognitionTestState.result;
      _isExecuting = false;
      notifyListeners();
    } catch (e) {
      _state = RecognitionTestState.failed;
      _displayResult = 'حدث خطأ أثناء الاختبار';
      _errorMessage = e.toString();
      _isExecuting = false;
      notifyListeners();
    }
  }

  /// نسخ التقرير النصي التشخيصي الكامل إلى الحافظة (البند 18 و 19)
  Future<bool> copyResult() async {
    final reportText = _session?.toClipboardReportText() ??
        'ISHARA SIMPLE TEST RESULT\nResult: $_displayResult';
    await Clipboard.setData(ClipboardData(text: reportText));
    return true;
  }

  /// إعادة تعيين جلسة الاختبار والعودة لوضع الجاهزية (البند 20)
  void resetTest() {
    _safetyTimeoutTimer?.cancel();
    _state = RecognitionTestState.idle;
    _collectedFrames = 0;
    _startSequenceId = null;
    _sessionStartTime = null;
    _session = null;
    _displayResult = '';
    _errorMessage = null;
    _isExecuting = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _safetyTimeoutTimer?.cancel();
    super.dispose();
  }
}
