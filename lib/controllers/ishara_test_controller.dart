import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara/ml/activity/ishara_sign_activity_detector.dart';
import 'package:ishara/ml/buffer/ishara_frame_ring_buffer.dart';
import 'package:ishara/ml/ctc/ishara_ctc_decoder.dart';
import 'package:ishara/ml/temporal/ishara_temporal_resampler.dart';
import 'package:ishara/models/ishara_recognition_test_session.dart';
import 'package:ishara/services/vision_detection_service.dart';

/// IsharaTestController
/// متحكم المسار الكامل لترجمة إشارات لغة الإشارة عبر Flutter Camera:
/// 1. Flutter Camera (Highest stable FPS, ResolutionPreset.medium 640x480)
/// 2. Latest Frame Only (إسقاط الفريمات المتأخرة ومنع تراكم Backlog)
/// 3. استخراج النقاط الـ 86 (KeypointMapper86 + KeypointNormalizer)
/// 4. اكتشاف بداية الحركة (Sign Start Detection + Body-Relative Motion)
/// 5. Pre-roll buffer (~10 فريمات ما قبل الحركة)
/// 6. تسجيل الحركة نفسها (Recording active sign frames)
/// 7. اكتشاف نهاية الحركة (Sign End Detection + Hysteresis)
/// 8. Post-roll buffer (~6 فريمات ما بعد الهدوء لحفظ الـ Handshape)
/// 9. Temporal Resampling -> 128 (استيفاء خطي زمني ذكي N -> 128 دون انتظار 128 فريم كاميرا)
/// 10. تشغيل الموديل الحالي [1, 128, 86, 2] -> [1, 29, 684]
/// 11. فك ترميز Greedy CTC
/// 12. ربط المفردات واستخراج الكلمات (Gloss Output)
class IsharaTestController extends ChangeNotifier {
  final VisionDetectionService _visionService;

  RecognitionTestState _state = RecognitionTestState.idle;
  int _collectedFrames = 0;
  DateTime? _sessionStartTime;
  DateTime? _signStartTime;
  Timer? _safetyTimeoutTimer;
  bool _isExecuting = false;
  bool _isSigningConfirmed = false;
  int _postRollRemaining = 6;

  // مخازن ما قبل وما بعد الحركة
  final List<IsharaBufferFrame> _preRollBuffer = [];
  final List<IsharaBufferFrame> _activeSignFrames = [];

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

  /// بدء جلسة اختبار جديدة والترقب لبداية الحركة
  void startSimpleTest() {
    if (!canStartTest) return;

    _errorMessage = null;
    _displayResult = '';
    _session = null;
    _collectedFrames = 0;
    _isExecuting = false;
    _isSigningConfirmed = false;
    _postRollRemaining = 6;
    _preRollBuffer.clear();
    _activeSignFrames.clear();
    _sessionStartTime = DateTime.now();

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

  /// معالجة كل فريم كاميرا جديد (Latest Frame Only)
  void onFrameProcessed(int latestSequenceId) {
    final latestFrame = _visionService.ringBuffer.getLatestFrame();
    if (latestFrame == null) return;

    final activityDetector = _visionService.continuousSignService.activityDetector;
    final actState = activityDetector.state;

    if (_state == RecognitionTestState.collecting) {
      if (!_isSigningConfirmed) {
        // ── 5. Pre-roll Buffer: حفظ آخر 10 فريمات قبل الحركة ──
        if (_preRollBuffer.length >= 10) {
          _preRollBuffer.removeAt(0);
        }
        _preRollBuffer.add(latestFrame.clone());

        // ── 4. اكتشاف بداية الحركة ──
        if (actState == SignActivityState.signing) {
          _isSigningConfirmed = true;
          _signStartTime = DateTime.now();
          // تفريغ مخزن الـ Pre-roll كاملاً في الإشارة
          _activeSignFrames.addAll(_preRollBuffer);
          _preRollBuffer.clear();
          _collectedFrames = _activeSignFrames.length;
          notifyListeners();
        }
      } else {
        // ── 6. تسجيل الحركة نفسها ──
        _activeSignFrames.add(latestFrame.clone());
        _collectedFrames = _activeSignFrames.length;
        notifyListeners();

        // ── 7. اكتشاف نهاية الحركة ──
        if (actState == SignActivityState.ending || actState == SignActivityState.ready) {
          // ── 8. Post-roll Buffer: جمع فريمات إضافية لحفظ شكل اليد ──
          if (_postRollRemaining > 0) {
            _postRollRemaining--;
          } else {
            // اكتملت الإشارة بالكامل! نتوقف فوراً دون انتظار 128 فريم
            _safetyTimeoutTimer?.cancel();
            _onSignCompleted();
          }
        }
      }
    } else if (_state == RecognitionTestState.idle) {
      // إبقاء مخزن الـ Pre-roll محدثاً دائماً حتى قبل الضغط
      if (_preRollBuffer.length >= 10) {
        _preRollBuffer.removeAt(0);
      }
      _preRollBuffer.add(latestFrame.clone());
    }
  }

  /// انتهاء مهلة الأمان (15 ثانية)
  void _onSafetyTimeout() {
    final duration = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inMilliseconds
        : 15000;

    _visionService.continuousSignService.activityDetector
        .forceFinalizeSignActivity(reason: 'TIMEOUT');

    if (_activeSignFrames.isNotEmpty && _activeSignFrames.length >= 10) {
      // إذا كانت هناك فريمات كافية ملتقطة، ننفذ التحليل فوراً بدلاً من الفشل
      _onSignCompleted();
    } else {
      _state = RecognitionTestState.failed;
      _displayResult = 'لم تكتمل البيانات، أعد المحاولة';
      _errorMessage = 'انتهت مهلة الـ 15 ثانية قبل اكتمال الإشارة';
      _session = IsharaRecognitionTestSession.failed(
        collectedFrames: _activeSignFrames.length,
        durationMs: duration,
        reason: 'TIMEOUT',
        errorMessage: _displayResult,
      );
      notifyListeners();
    }
  }

  /// اكتمال الإشارة الحقيقية وتنفيذ الاستيفاء والاستنتاج الفوري
  Future<void> _onSignCompleted() async {
    if (_isExecuting) return;
    _isExecuting = true;
    _state = RecognitionTestState.processing;
    _displayResult = 'جاري التحليل...';
    notifyListeners();

    try {
      final startTime = _signStartTime ?? _sessionStartTime ?? DateTime.now();
      final totalDurationMs = DateTime.now().difference(startTime).inMilliseconds;
      final inferenceStart = DateTime.now();

      // إغلاق مقطع النشاط في الكاشف
      _visionService.continuousSignService.activityDetector
          .forceFinalizeSignActivity(reason: 'MOTION_QUIET');

      // ── 9. Temporal Resampling -> 128 ──
      // استيفاء الفريمات الملتقطة (سواء كانت 20 أو 45 فريم) إلى 128 إطاراً بالضبط
      final resampled = IsharaTemporalResampler.resample(
        _activeSignFrames,
        durationMs: totalDurationMs,
      );

      // تحليل جودة التسلسل
      final quality = _visionService.ringBuffer.analyzeCurrentSequence(
        captureTime: DateTime.now(),
      );

      // ── 10. تشغيل الموديل الحالي [1, 128, 86, 2] -> [1, 29, 684] ──
      final rawOutput = await _visionService.tfliteService.runRealSequenceInference(
        resampled.modelInput,
      );
      final inferenceTimeMs = DateTime.now().difference(inferenceStart).inMilliseconds;

      if (!rawOutput.isSuccess) {
        _state = RecognitionTestState.failed;
        _displayResult = 'فشل معالجة الموديل';
        _errorMessage = rawOutput.errorMessage;
        _isExecuting = false;
        notifyListeners();
        return;
      }

      // ── 11. فك ترميز Greedy CTC ──
      final ctcResult = IsharaCtcDecoder.decodeRawArgmax(rawOutput.rawArgmax);

      // ── 12. ربط المفردات واستخراج الكلمات (Gloss Output) ──
      final glosses = _visionService.vocabService.mapIdsToGlosses(ctcResult.decodedIds);

      String finalDisplay;
      if (quality.rawCoveragePercent < 55.0) {
        finalDisplay = 'الإشارة غير واضحة، أعد المحاولة';
      } else if (ctcResult.decodedIds.isEmpty) {
        finalDisplay = 'لم يتم التعرف على إشارة واضحة';
      } else {
        finalDisplay = glosses.join(' - ');
      }

      final actDetector = _visionService.continuousSignService.activityDetector;
      _session = IsharaRecognitionTestSession(
        capturedAt: DateTime.now(),
        collectedFrames: _activeSignFrames.length,
        targetFrames: 128,
        durationMs: totalDurationMs,
        sequenceQualityPct: quality.rawCoveragePercent,
        imputationPct: quality.imputationPercent,
        rhCoveragePct: quality.rhCoveragePercent,
        lhCoveragePct: quality.lhCoveragePercent,
        lipsCoveragePct: quality.lipsCoveragePercent,
        bodyCoveragePct: quality.bodyCoveragePercent,
        inputShape: resampled.modelInput.shape,
        outputShape: rawOutput.outputShape,
        inferencePass: true,
        inferenceTimeMs: inferenceTimeMs,
        rawArgmaxIds: rawOutput.rawArgmax,
        ctcIds: ctcResult.decodedIds,
        glosses: glosses,
        finalResultDisplay: finalDisplay,
        signStartDetected: actDetector.signStartTime != null,
        signEndDetected: actDetector.signEndTime != null,
        endReason: actDetector.endReason.isNotEmpty ? actDetector.endReason : 'MOTION_QUIET',
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

  /// نسخ التقرير النصي التشخيصي الكامل
  Future<bool> copyResult() async {
    final reportText = _session?.toClipboardReportText() ??
        'ISHARA SIMPLE TEST RESULT\nResult: $_displayResult';
    await Clipboard.setData(ClipboardData(text: reportText));
    return true;
  }

  /// تصفير الجلسة والعودة للجاهزية
  void resetTest() {
    _safetyTimeoutTimer?.cancel();
    _state = RecognitionTestState.idle;
    _collectedFrames = 0;
    _isSigningConfirmed = false;
    _postRollRemaining = 6;
    _preRollBuffer.clear();
    _activeSignFrames.clear();
    _sessionStartTime = null;
    _signStartTime = null;
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
