import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara/models/ishara_test_state.dart';
import 'package:ishara/models/real_inference_result.dart';
import 'package:ishara/services/vision_detection_service.dart';

/// IsharaTestController
/// Controller مخصص لإدارة وتوجيه تجربة الاختبار المبسطة والآلية:
/// - إدارة دورة حياة الاختبار وحالاته المنظمة (IsharaTestState).
/// - تشغيل العد التنازلي التلقائي (3.. 2.. 1).
/// - عداد الإطارات الدقيق (Frames: 0..128 / 128) أثناء التسجيل فقط.
/// - تنفيذ الاستنتاج الآلي ومقارنة الحركتين A و B.
/// - توليد ونسخ التقرير النهائي بضغطة واحدة.
class IsharaTestController extends ChangeNotifier {
  final VisionDetectionService _visionService;

  IsharaTestState _state = IsharaTestState.idle;
  int _countdown = 3;
  String _activeTest = 'Test A';
  int _recordedFrames = 0;
  int? _startSequenceId;
  bool _isExecuting = false;

  SingleRealInferenceResult? _resultA;
  SingleRealInferenceResult? _resultB;
  RealInferenceComparisonResult? _comparison;
  String? _finalReport;
  String? _errorMessage;

  IsharaTestController(this._visionService);

  // ── Getters ──
  IsharaTestState get state => _state;
  int get countdown => _countdown;
  String get activeTestLabel => _activeTest;
  int get recordedFrames => _recordedFrames;
  bool get isRecording => _state.isRecording;
  bool get isCountdown => _state.isCountdown;
  bool get isCompleted => _state.isCompleted;
  bool get isTestADone => _state.isTestADone;
  bool get isTestBDone => _state.isTestBDone;
  SingleRealInferenceResult? get resultA => _resultA;
  SingleRealInferenceResult? get resultB => _resultB;
  RealInferenceComparisonResult? get comparison => _comparison;
  String? get finalReport => _finalReport;
  String? get errorMessage => _errorMessage;

  bool get canStartTestA => _state == IsharaTestState.idle && !_isExecuting;

  bool get canStartTestB =>
      _state == IsharaTestState.readyForB && !_isExecuting;

  /// بدء الاختبار الأول (TEST A) مع العد التنازلي (3.. 2.. 1)
  Future<void> startTestA() async {
    if (!canStartTestA) return;

    _errorMessage = null;
    _activeTest = 'Test A';
    _state = IsharaTestState.countdown;
    _countdown = 3;
    notifyListeners();

    await _runCountdown(() {
      final latestId =
          _visionService.ringBuffer.getStatus().latestFrameSequenceId ?? 0;
      _startSequenceId = latestId;
      _recordedFrames = 0;
      _state = IsharaTestState.recordingA;
      notifyListeners();
    });
  }

  /// بدء الاختبار الثاني (TEST B) مع العد التنازلي (3.. 2.. 1)
  Future<void> startTestB() async {
    if (!canStartTestB) return;

    _errorMessage = null;
    _activeTest = 'Test B';
    _state = IsharaTestState.countdown;
    _countdown = 3;
    notifyListeners();

    await _runCountdown(() {
      final latestId =
          _visionService.ringBuffer.getStatus().latestFrameSequenceId ?? 0;
      _startSequenceId = latestId;
      _recordedFrames = 0;
      _state = IsharaTestState.recordingB;
      notifyListeners();
    });
  }

  /// تشغيل العد التنازلي 3.. 2.. 1
  Future<void> _runCountdown(VoidCallback onFinished) async {
    for (int i = 3; i > 1; i--) {
      await Future.delayed(const Duration(seconds: 1));
      if (_state != IsharaTestState.countdown) return;
      _countdown--;
      notifyListeners();
    }
    await Future.delayed(const Duration(seconds: 1));
    if (_state != IsharaTestState.countdown) return;
    onFinished();
  }

  /// يتم استدعاؤها مع كل إطار كاميرا تتم معالجته في الخلفية
  void onFrameProcessed(int latestSequenceId) {
    if (!_state.isRecording) return;
    if (_startSequenceId == null) return;

    final count = (latestSequenceId - _startSequenceId!).clamp(0, 128);
    _recordedFrames = count;
    notifyListeners();

    // عند اكتمال الـ 128 إطاراً للحركة الحالية: نبدأ الاستنتاج فوراً وبشكل آلي
    if (count >= 128 && !_isExecuting) {
      _onRecordingWindowCompleted();
    }
  }

  /// عند اكتمال نافذة الـ 128 إطاراً
  Future<void> _onRecordingWindowCompleted() async {
    _isExecuting = true;

    try {
      if (_state == IsharaTestState.recordingA) {
        _state = IsharaTestState.processingA;
        notifyListeners();

        final result = await _visionService.realInferenceTestService
            .captureAndInfer(testLabel: 'TEST A');
        _resultA = result;

        if (!result.isSuccess) {
          _errorMessage = result.errorMessage;
        }

        _state = IsharaTestState.readyForB;
        _recordedFrames = 0;
        _startSequenceId = null;
        _isExecuting = false;
        notifyListeners();
      } else if (_state == IsharaTestState.recordingB) {
        _state = IsharaTestState.processingB;
        notifyListeners();

        final result = await _visionService.realInferenceTestService
            .captureAndInfer(testLabel: 'TEST B');
        _resultB = result;
        _comparison = _visionService.realInferenceTestService.comparison;
        _finalReport = _visionService.realInferenceTestService.generateReport();

        if (!result.isSuccess) {
          _errorMessage = result.errorMessage;
        }

        _state = IsharaTestState.completed;
        _recordedFrames = 0;
        _startSequenceId = null;
        _isExecuting = false;
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = e.toString();
      _isExecuting = false;
      notifyListeners();
    }
  }

  /// نسخ التقرير النهائي الكامل للحافظة بنقرة واحدة
  Future<bool> copyResult() async {
    final report =
        _finalReport ??
        _visionService.realInferenceTestService.generateReport();
    await Clipboard.setData(ClipboardData(text: report));
    return true;
  }

  /// إعادة تعيين وتصفير الاختبار للبدء من جديد مع بقاء الكاميرا تعمل طبيعياً
  void reset() {
    _state = IsharaTestState.idle;
    _countdown = 3;
    _activeTest = 'Test A';
    _recordedFrames = 0;
    _startSequenceId = null;
    _resultA = null;
    _resultB = null;
    _comparison = null;
    _finalReport = null;
    _errorMessage = null;
    _isExecuting = false;
    _visionService.realInferenceTestService.resetSession();
    notifyListeners();
  }
}
