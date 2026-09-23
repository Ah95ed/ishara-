import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara/ml/ctc/ishara_ctc_decoder.dart';
import 'package:ishara/ml/diagnostics/ishara_pipeline_tracer.dart';
import 'package:ishara/models/ishara_recognition_test_session.dart';
import 'package:ishara/services/vision_detection_service.dart';

/// IsharaTestController
/// متحكم المسار البسيط لترجمة إشارات لغة الإشارة مع نظام التتبع والتشخيص الشامل:
/// 1. الكاميرا تستمر في البث (~30 FPS)
/// 2. استقبال أحدث إطار فقط (Latest Frame Only)
/// 3. استخراج المعالم [86, 2] وتغذية الـ Ring Buffer
/// 4. تجميع 128 إطار Pose جديدة بعد الضغط على "ابدأ الاختبار"
/// 5. توثيق وتسجيل كافة مراحل المعالجة العشر في IsharaPipelineTracer
/// 6. Snapshot زمني مرتب [1, 128, 86, 2] Float32
/// 7. فحص خلو المصفوفة من NaN/Inf وتشغيل موديل TFLite [1, 29, 684]
/// 8. فك ترميز Greedy CTC
/// 9. ربط المفردات واستخراج الكلمات
/// 10. إتاحة نسخ التقرير الكامل للحافظة بنقرة واحدة
class IsharaTestController extends ChangeNotifier {
  final VisionDetectionService _visionService;

  RecognitionTestState _state = RecognitionTestState.idle;
  int _collectedFrames = 0;
  DateTime? _sessionStartTime;
  bool _isExecuting = false;
  Timer? _testTimeoutTimer;

  IsharaRecognitionTestSession? _session;
  String _displayResult = '';
  String? _errorMessage;

  IsharaTestController(this._visionService);

  // ── Getters ──
  RecognitionTestState get state => _state;
  bool get isIdle => _state.isIdle;
  bool get isCollecting => _state.isCollecting;
  bool get isProcessing => _state.isProcessing;
  bool get isTesting => _state.isCollecting || _state.isProcessing;
  bool get isResult => _state.isResult;
  bool get isFailed => _state.isFailed;

  int get collectedFrames => _collectedFrames;
  int get targetFrames => 128;
  String get displayResult => _displayResult;
  String get resultGloss => _displayResult;
  IsharaRecognitionTestSession? get session => _session;
  String? get errorMessage => _errorMessage;

  IsharaPipelineTracer get tracer => IsharaPipelineTracer.instance;
  PipelineStage get currentStage => tracer.currentStage;
  String get traceMarkdownReport => tracer.toMarkdownReport();

  bool get canStartTest =>
      !_isExecuting && (_state.isIdle || _state.isResult || _state.isFailed);

  /// بدء اختبار جديد وتجميع 128 إطاراً جديدة فقط
  void startSimpleTest() {
    if (!canStartTest) return;

    _testTimeoutTimer?.cancel();
    _errorMessage = null;
    _displayResult = '';
    _session = null;
    _collectedFrames = 0;
    _isExecuting = false;
    _sessionStartTime = DateTime.now();

    // بدء جلسة التتبع الشاملة وتفريغ الـ Buffer لاستقبال الفريمات الجديدة فقط
    tracer.startNewSession();
    _visionService.ringBuffer.clearForTesting();

    _state = RecognitionTestState.collecting;
    notifyListeners();

    // مؤقت أمان 20 ثانية لتنبيه المستخدم إذا لم تكتمل الفريمات مع حفظ سبب عدم الاكتمال
    _testTimeoutTimer = Timer(const Duration(seconds: 20), _onTestTimeout);
  }

  /// انتهاء مهلة الأمان (20 ثانية) دون الوصول لـ 128 إطاراً
  void _onTestTimeout() {
    if (_state != RecognitionTestState.collecting) return;

    final bufStatus = _visionService.ringBuffer.getStatus();
    tracer.recordError(
      stage: PipelineStage.ringBuffer,
      error:
          'انتهت مهلة الـ 20 ثانية ولم يكتمل تجميع 128 إطاراً (تم تجميع ${_collectedFrames} فقط من 128).\n'
          'السبب المحتمل: عدم وضوح الشخص أمام الكاميرا (تخطى البفر ${bufStatus.totalFramesSkippedNoPerson} فريم لغياب الشخص).',
    );

    _errorMessage =
        'انتهت المهلة قبل جمع 128 إطاراً (تم جمع $_collectedFrames/128). تأكد من ظهور الرأس والأكتاف واليدين بوضوح.';
    _displayResult = 'لم تكتمل 128 إشارة - انسخ تقرير التتبع';
    _state = RecognitionTestState.failed;
    notifyListeners();
  }

  /// معالجة كل فريم كاميرا جديد يتم إدخاله في الـ Ring Buffer
  void onFrameProcessed(int latestSequenceId) {
    if (_state != RecognitionTestState.collecting) return;
    if (_isExecuting) return;

    final bufStatus = _visionService.ringBuffer.getStatus();
    _collectedFrames = bufStatus.frameCount;

    // تحديث بيانات التتبع اللحظية لحالة الـ Ring Buffer
    tracer.updateRingBufferProgress(
      currentCount: _collectedFrames,
      framesAdded: bufStatus.totalFramesAdded,
      framesSkippedNoPerson: bufStatus.totalFramesSkippedNoPerson,
      duplicatesRejected: bufStatus.duplicateFramesRejected,
      oldestId: bufStatus.oldestFrameSequenceId,
      newestId: bufStatus.latestFrameSequenceId,
    );

    // تحديث الواجهة دورياً لعرض العداد اللحظي في التفاصيل
    if (_collectedFrames % 10 == 0) {
      notifyListeners();
    }

    // عند اكتمال 128 إطاراً جديدة تماماً: ننفذ الاستنتاج فوراً
    if (_collectedFrames >= 128) {
      _testTimeoutTimer?.cancel();
      _on128FramesCollected();
    }
  }

  /// تنفيذ الاستنتاج عند اكتمال 128 إطاراً
  Future<void> _on128FramesCollected() async {
    if (_isExecuting) return;
    _isExecuting = true;
    _state = RecognitionTestState.processing;
    notifyListeners();

    try {
      // ── STAGE 6: MODEL INPUT TENSOR ──
      tracer.currentStage = PipelineStage.modelInputValidation;

      final modelInput = _visionService.ringBuffer.buildModelInput(
        applyHandsBackwardFill: true,
      );

      if (modelInput == null) {
        throw Exception(
          'تعذر استخراج تسلسل الإطارات من الـ Ring Buffer (RingBuffer.buildModelInput returned null)',
        );
      }

      // تسجيل وتحليل مصفوفة الإدخال في التتبع
      tracer.modelInputTelemetry = ModelInputTelemetry.fromFlatData(
        modelInput.flatData,
        shape: modelInput.shape,
        handsBackwardFilled: true,
      );

      if (!listEquals(modelInput.shape, const [1, 128, 86, 2])) {
        throw Exception('شكل الإدخال غير مطابق: ${modelInput.shape} (المتوقع [1, 128, 86, 2])');
      }
      if (modelInput.nanCount > 0 || modelInput.infCount > 0) {
        throw Exception(
          'تحتوي المدخلات على قيم غير صالحة (NaN: ${modelInput.nanCount}, Inf: ${modelInput.infCount})',
        );
      }

      // ── STAGE 7: TFLITE INFERENCE ──
      tracer.currentStage = PipelineStage.tfliteInference;

      final inferenceStart = DateTime.now();
      final rawOutput = await _visionService.tfliteService.runRealSequenceInference(
        modelInput,
      );
      final inferenceTimeMs = DateTime.now().difference(inferenceStart).inMilliseconds;

      if (!rawOutput.isSuccess) {
        throw Exception(rawOutput.errorMessage ?? 'فشل تنفيذ استنتاج موديل TFLite');
      }

      // ── STAGE 8: CTC DECODING ──
      tracer.currentStage = PipelineStage.ctcDecoding;
      final ctcResult = IsharaCtcDecoder.decodeRawArgmax(rawOutput.rawArgmax);

      // ── STAGE 9: VOCABULARY MAPPING ──
      tracer.currentStage = PipelineStage.vocabMapping;
      final glosses = _visionService.vocabService.mapIdsToGlosses(ctcResult.decodedIds);

      final blankCount = rawOutput.rawArgmax.where((id) => id == 0).length;
      final uniqueClasses =
          rawOutput.rawArgmax.where((id) => id != 0).toSet().toList()..sort();

      tracer.modelOutputTelemetry = ModelOutputTelemetry(
        inferenceTimeMs: inferenceTimeMs,
        outputShape: rawOutput.outputShape,
        nanCount: rawOutput.nanCount,
        infCount: rawOutput.infCount,
        minVal: rawOutput.outputMin,
        maxVal: rawOutput.outputMax,
        meanVal: rawOutput.outputMean,
        stdDev: rawOutput.outputStdDev,
        rawArgmax: rawOutput.rawArgmax,
        blankCount: blankCount,
        uniqueNonBlankClasses: uniqueClasses,
        ctcDecodedIds: ctcResult.decodedIds,
        glosses: glosses,
      );

      // ── STAGE 10: RESULT ──
      if (glosses.isNotEmpty) {
        _displayResult = glosses.join(' ');
      } else {
        _displayResult = 'لم يتم التعرف على إشارة واضحة';
      }

      tracer.finalGlossResult = _displayResult;
      tracer.currentStage = PipelineStage.completed;
      tracer.testEndTime = DateTime.now();

      final totalDurationMs = _sessionStartTime != null
          ? DateTime.now().difference(_sessionStartTime!).inMilliseconds
          : 0;

      final quality = _visionService.ringBuffer.analyzeCurrentSequence();
      _session = IsharaRecognitionTestSession(
        capturedAt: DateTime.now(),
        collectedFrames: 128,
        targetFrames: 128,
        durationMs: totalDurationMs,
        sequenceQualityPct: quality.rawCoveragePercent,
        imputationPct: quality.imputationPercent,
        rhCoveragePct: quality.rhCoveragePercent,
        lhCoveragePct: quality.lhCoveragePercent,
        lipsCoveragePct: quality.lipsCoveragePercent,
        bodyCoveragePct: quality.bodyCoveragePercent,
        inputShape: modelInput.shape,
        outputShape: rawOutput.outputShape,
        inferencePass: true,
        inferenceTimeMs: inferenceTimeMs,
        rawArgmaxIds: rawOutput.rawArgmax,
        ctcIds: ctcResult.decodedIds,
        glosses: glosses,
        finalResultDisplay: _displayResult,
        signStartDetected: true,
        signEndDetected: true,
        endReason: 'BUFFER_128',
        errors: 'NONE',
      );

      _state = RecognitionTestState.result;
    } catch (e, stack) {
      debugPrint('[IsharaTestController] ⚠️ Error during inference: $e\n$stack');
      _errorMessage = e.toString();
      _displayResult = 'حدث خطأ: $e';

      tracer.recordError(
        stage: tracer.currentStage,
        error: e,
        stackTrace: stack,
      );

      _state = RecognitionTestState.failed;
    } finally {
      _isExecuting = false;
      notifyListeners();
    }
  }

  /// نسخ تقرير التتبع والتشخيص الشامل الكامل للحافظة بنقرة واحدة
  Future<bool> copyFullTraceReport() async {
    final reportText = tracer.toMarkdownReport();
    await Clipboard.setData(ClipboardData(text: reportText));
    return true;
  }

  /// تصفير الجلسة والعودة للجاهزية
  void resetTest() {
    _testTimeoutTimer?.cancel();
    _state = RecognitionTestState.idle;
    _collectedFrames = 0;
    _sessionStartTime = null;
    _session = null;
    _displayResult = '';
    _errorMessage = null;
    _isExecuting = false;
    _visionService.ringBuffer.clearForTesting();
    notifyListeners();
  }

  @override
  void dispose() {
    _testTimeoutTimer?.cancel();
    super.dispose();
  }
}
