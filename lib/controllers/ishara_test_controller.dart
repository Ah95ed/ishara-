import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara/ml/ctc/ishara_ctc_decoder.dart';
import 'package:ishara/models/ishara_recognition_test_session.dart';
import 'package:ishara/services/vision_detection_service.dart';

/// IsharaTestController
/// متحكم المسار البسيط الأصلي لترجمة إشارات لغة الإشارة:
/// 1. الكاميرا تستمر في البث (~30 FPS)
/// 2. استقبال أحدث إطار فقط (Latest Frame Only)
/// 3. استخراج المعالم [86, 2] وتغذية الـ Ring Buffer
/// 4. تجميع 128 إطار Pose جديدة بعد الضغط على "ابدأ الاختبار"
/// 5. Snapshot زمني مرتب [1, 128, 86, 2] Float32
/// 6. التحقق من أبعاد المدخلات وخلوها من NaN/Inf
/// 7. تشغيل موديل TFLite الحالي [1, 128, 86, 2] -> [1, 29, 684]
/// 8. فك ترميز Greedy CTC
/// 9. ربط المفردات واستخراج النتيجة النصية أسفل الكاميرا
/// 10. إعادة تفعيل زر الاختبار لجلسة جديدة
class IsharaTestController extends ChangeNotifier {
  final VisionDetectionService _visionService;

  RecognitionTestState _state = RecognitionTestState.idle;
  int _collectedFrames = 0;
  DateTime? _sessionStartTime;
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
  bool get isTesting => _state.isCollecting || _state.isProcessing;
  bool get isResult => _state.isResult;
  bool get isFailed => _state.isFailed;

  int get collectedFrames => _collectedFrames;
  int get targetFrames => 128;
  String get displayResult => _displayResult;
  String get resultGloss => _displayResult;
  IsharaRecognitionTestSession? get session => _session;
  String? get errorMessage => _errorMessage;

  bool get canStartTest => !_isExecuting && (_state.isIdle || _state.isResult || _state.isFailed);

  /// بدء اختبار جديد وتجميع 128 إطاراً جديدة فقط
  void startSimpleTest() {
    if (!canStartTest) return;

    _errorMessage = null;
    _displayResult = '';
    _session = null;
    _collectedFrames = 0;
    _isExecuting = false;
    _sessionStartTime = DateTime.now();

    // تفريغ الـ Ring Buffer لضمان استقبال فريمات جديدة فقط بعد ضغط الزر
    _visionService.ringBuffer.clearForTesting();

    _state = RecognitionTestState.collecting;
    notifyListeners();
  }

  /// معالجة كل فريم كاميرا جديد يتم إدخاله في الـ Ring Buffer
  void onFrameProcessed(int latestSequenceId) {
    if (_state != RecognitionTestState.collecting) return;
    if (_isExecuting) return;

    // متابعة عدد الفريمات المحفوظة داخل الـ Ring Buffer داخلياً
    _collectedFrames = _visionService.ringBuffer.count;

    // عند اكتمال 128 إطاراً جديدة تماماً: ننفذ الاستنتاج فوراً
    if (_collectedFrames >= 128) {
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
      // 1. أخذ Snapshot زمني مرتب عميق [1, 128, 86, 2]
      final modelInput = _visionService.ringBuffer.buildModelInput(
        applyHandsBackwardFill: true,
      );

      if (modelInput == null) {
        throw Exception('تعذر استخراج تسلسل الإطارات من الـ Ring Buffer');
      }

      // 2. التحقق الصارم من صحة المدخلات قبل التمرير للموديل
      // Batch=1, Frames=128, Points=86, Coordinates=2
      if (!listEquals(modelInput.shape, const [1, 128, 86, 2])) {
        throw Exception('شكل الإدخال غير مطابق: ${modelInput.shape}');
      }
      if (modelInput.nanCount > 0 || modelInput.infCount > 0) {
        throw Exception('تحتوي المدخلات على قيم غير صالحة (NaN: ${modelInput.nanCount}, Inf: ${modelInput.infCount})');
      }

      // 3. تشغيل موديل TFLite الحالي [1, 128, 86, 2] -> [1, 29, 684]
      final inferenceStart = DateTime.now();
      final rawOutput = await _visionService.tfliteService.runRealSequenceInference(
        modelInput,
      );
      final inferenceTimeMs = DateTime.now().difference(inferenceStart).inMilliseconds;

      if (!rawOutput.isSuccess) {
        throw Exception(rawOutput.errorMessage ?? 'فشل تنفيذ استنتاج الموديل');
      }

      // 4. فك ترميز Greedy CTC: Argmax -> Collapse consecutive duplicates -> Remove blank 0
      final ctcResult = IsharaCtcDecoder.decodeRawArgmax(rawOutput.rawArgmax);

      // 5. ربط المفردات واستخراج الكلمات (Gloss Mapping)
      final glosses = _visionService.vocabService.mapIdsToGlosses(ctcResult.decodedIds);

      // 6. إعداد النتيجة المعروضة (One clean result word/phrase)
      if (glosses.isNotEmpty) {
        _displayResult = glosses.join(' ');
      } else {
        _displayResult = 'لم يتم التعرف على إشارة واضحة';
      }

      final totalDurationMs = _sessionStartTime != null
          ? DateTime.now().difference(_sessionStartTime!).inMilliseconds
          : 0;

      // تقرير الجودة الداخلي (يخزن للمطورين في الذاكرة دون عرضه في الواجهة)
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
    } catch (e) {
      debugPrint('[IsharaTestController] ⚠️ Error during inference: $e');
      _errorMessage = e.toString();
      _displayResult = 'حدث خطأ أثناء الاختبار';
      _state = RecognitionTestState.failed;
    } finally {
      _isExecuting = false;
      notifyListeners();
    }
  }

  /// نسخ التقرير النصي التشخيصي الكامل (للمطورين عند الحاجة)
  Future<bool> copyResult() async {
    final reportText = _session?.toClipboardReportText() ??
        'ISHARA TEST RESULT\nResult: $_displayResult';
    await Clipboard.setData(ClipboardData(text: reportText));
    return true;
  }

  /// تصفير الجلسة والعودة للجاهزية دون إعادة تشغيل الكاميرا
  void resetTest() {
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
    super.dispose();
  }
}
