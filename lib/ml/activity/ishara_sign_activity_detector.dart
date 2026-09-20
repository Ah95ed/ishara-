import 'dart:math' as math;

import 'package:ishara/ml/buffer/ishara_frame_ring_buffer.dart';

/// حالات نشاط الإشارة (Sign Activity States)
enum SignActivityState {
  idle, // سكون تام أو حركة اهتزاز طبيعية (Resting/Jitter)
  signing, // نشاط حركي مستمر يمثل أداء إشارة
  ending, // هدوء حركة بعد الإشارة للتأكد من اكتمالها
  ready, // الإشارة اكتملت وجاهزة للتقييم والقبول
}

extension SignActivityStateExt on SignActivityState {
  String get nameUpper {
    switch (this) {
      case SignActivityState.idle:
        return 'IDLE';
      case SignActivityState.signing:
        return 'SIGNING';
      case SignActivityState.ending:
        return 'ENDING';
      case SignActivityState.ready:
        return 'READY';
    }
  }
}

/// إعدادات كاشف نشاط الإشارة القابلة للتخصيص
class SignActivityConfig {
  final int
  minStartDurationMs; // مدة استمرار الحركة لاعتماد بداية الإشارة (150-250ms)
  final int
  minEndDurationMs; // مدة استمرار الهدوء لاعتماد نهاية الإشارة (300-500ms)
  final int maximumSignDurationMs; // أقصى مدة مسموحة لاستمرار الإشارة كإجراء أمان (12 ثانية)
  final double
  defaultStartThreshold; // عتبة الحركة المبدئية قبل اكتمال الـ Baseline
  final double defaultEndThreshold; // عتبة الحركة المبدئية لاعتبار الهدوء
  final double startMargin; // هامش إضافي لبداية الإشارة لضمان Hysteresis
  final double endMargin; // هامش إضافي لنهاية الإشارة
  final double
  baselineStdDevMultiplier; // معامل الانحراف المعياري للـ Baseline الديناميكي
  final double
  minMotionSensitivity; // الحد الأدنى لحساسية الحركة لمنع التشغيل الكاذب
  final int baselineWindowSize; // عدد الإطارات لحساب الـ Baseline (~1 ثانية)

  const SignActivityConfig({
    this.minStartDurationMs = 200,
    this.minEndDurationMs = 400,
    this.maximumSignDurationMs = 12000,
    this.defaultStartThreshold = 0.025,
    this.defaultEndThreshold = 0.015,
    this.startMargin = 0.010,
    this.endMargin = 0.004,
    this.baselineStdDevMultiplier = 2.5,
    this.minMotionSensitivity = 0.015,
    this.baselineWindowSize = 20,
  });
}

/// لقطة تشخيصية لحظية لكاشف نشاط الإشارة
class SignActivityDiagnostic {
  final SignActivityState state;
  final double currentMotion;
  final double baselineMean;
  final double baselineStdDev;
  final double startThreshold;
  final double endThreshold;
  final double rightHandMotion;
  final double leftHandMotion;
  final double lipsMotion;
  final double bodyMotion;
  final int stateDurationMs;
  final int signSegmentId;
  final String endReason;

  const SignActivityDiagnostic({
    required this.state,
    required this.currentMotion,
    required this.baselineMean,
    required this.baselineStdDev,
    required this.startThreshold,
    required this.endThreshold,
    required this.rightHandMotion,
    required this.leftHandMotion,
    required this.lipsMotion,
    required this.bodyMotion,
    required this.stateDurationMs,
    required this.signSegmentId,
    this.endReason = 'NONE',
  });
}

/// IsharaSignActivityDetector
/// كاشف نشاط وبداية ونهاية إشارة لغة الإشارة:
/// - يعتمد حصرياً على إحداثيات النقاط الـ 86 المطبعة (Normalized Keypoints)
/// - يستبعد تماماً النقاط المعوضة (Imputed Points) من حساب الحركة
/// - يحسب الحركة لكل جزء: اليد اليمنى، اليد اليسرى، الشفاه، الجسم
/// - يحسب خط الأساس الديناميكي (Adaptive Motion Baseline) للاهتزاز الطبيعي (Jitter)
/// - يطبق Hysteresis صريح لمنع التذبذب (Start Threshold > End Threshold)
/// - يطبق سقف زمني صارم (12 ثانية) لمنع تعليق الإشارة إلى الأبد
class IsharaSignActivityDetector {
  final SignActivityConfig config;

  SignActivityState _state = SignActivityState.idle;
  int _signSegmentId = 0;
  String _endReason = 'NONE';

  IsharaBufferFrame? _previousFrame;
  DateTime? _stateEnteredTime;
  DateTime? _motionAboveStartTime;
  DateTime? _motionBelowEndTime;
  DateTime? _signStartTime;
  DateTime? _signEndTime;

  // نافذة خط الأساس للحركة الهادئة (Adaptive Baseline Window)
  final List<double> _baselineBuffer = [];
  double _baselineMean = 0.008;
  double _baselineStdDev = 0.003;

  // مقاييس الحركة اللحظية
  double _currentMotion = 0.0;
  double _peakMotion = 0.0;
  double _rhMotion = 0.0;
  double _lhMotion = 0.0;
  double _lipsMotion = 0.0;
  double _bodyMotion = 0.0;

  IsharaSignActivityDetector({this.config = const SignActivityConfig()});

  SignActivityState get state => _state;
  int get signSegmentId => _signSegmentId;
  String get endReason => _endReason;
  double get currentMotion => _currentMotion;
  double get peakMotion => _peakMotion;
  double get baselineMean => _baselineMean;
  double get baselineStdDev => _baselineStdDev;
  DateTime? get signStartTime => _signStartTime;
  DateTime? get signEndTime => _signEndTime;

  int get signDurationMs {
    if (_signStartTime == null) return 0;
    final end = _signEndTime ?? DateTime.now();
    return end.difference(_signStartTime!).inMilliseconds;
  }

  /// العتبة الديناميكية المحسوبة لبداية الإشارة مع Hysteresis
  double get dynamicStartThreshold {
    final adaptive =
        _baselineMean +
        (_baselineStdDev * config.baselineStdDevMultiplier) +
        config.startMargin;
    return math.max(adaptive, config.minMotionSensitivity);
  }

  /// العتبة الديناميكية المحسوبة لنهاية الإشارة
  double get dynamicEndThreshold {
    final adaptive = _baselineMean + (_baselineStdDev * 0.8) + config.endMargin;
    return math.max(adaptive, config.minMotionSensitivity * 0.5);
  }

  /// إغلاق وإنهاء المقطع الحركي الحالي قسراً (Safety Finalization)
  void forceFinalizeSignActivity({String reason = 'FRAME_LIMIT'}) {
    _endReason = reason;
    _signEndTime ??= DateTime.now();
    _state = SignActivityState.idle;
    _motionAboveStartTime = null;
    _motionBelowEndTime = null;
  }

  /// معالجة إطار جديد وتحديث حالة النشاط
  SignActivityDiagnostic processFrame(IsharaBufferFrame frame) {
    final now = frame.timestamp;
    _stateEnteredTime ??= now;

    if (_previousFrame == null) {
      _previousFrame = frame.clone();
      return _buildDiagnostic(now);
    }

    // 1. حساب الحركة بين الإطار الحالي والسابق مع استبعاد التعويض
    _calculateFrameMotion(current: frame, previous: _previousFrame!);
    _previousFrame = frame.clone();

    // 2. تحديث الـ Baseline أثناء السكون (IDLE)
    if (_state == SignActivityState.idle) {
      _updateBaseline(_currentMotion);
    }

    final startThreshold = dynamicStartThreshold;
    final endThreshold = dynamicEndThreshold;

    // 3. آلة الحالات الزمنية (Temporal State Machine)
    switch (_state) {
      case SignActivityState.idle:
        if (_currentMotion >= startThreshold) {
          _motionAboveStartTime ??= now;
          final duration = now
              .difference(_motionAboveStartTime!)
              .inMilliseconds;
          if (duration >= config.minStartDurationMs) {
            _transitionTo(SignActivityState.signing, now);
            _signSegmentId++;
            _signStartTime = now;
            _signEndTime = null;
            _peakMotion = _currentMotion;
            _endReason = 'NONE';
            _motionAboveStartTime = null;
          }
        } else {
          _motionAboveStartTime = null;
        }
        break;

      case SignActivityState.signing:
        if (_currentMotion > _peakMotion) {
          _peakMotion = _currentMotion;
        }

        // فحص أمان أقصى مدة للإشارة لمنع بقائها معلقة للأبد (Requirement 15)
        final signDuration = _signStartTime != null
            ? now.difference(_signStartTime!).inMilliseconds
            : 0;
        if (signDuration >= config.maximumSignDurationMs) {
          _endReason = 'MAX_DURATION';
          _signEndTime = now;
          _transitionTo(SignActivityState.idle, now);
          _motionBelowEndTime = null;
          break;
        }

        if (_currentMotion < endThreshold) {
          _motionBelowEndTime ??= now;
          final duration = now.difference(_motionBelowEndTime!).inMilliseconds;
          if (duration >= config.minEndDurationMs) {
            _endReason = 'MOTION_QUIET';
            _transitionTo(SignActivityState.ending, now);
            _signEndTime = now;
            _motionBelowEndTime = null;
          }
        } else {
          _motionBelowEndTime = null;
        }
        break;

      case SignActivityState.ending:
        // إذا عادت الحركة بشكل مفاجئ نعود لـ SIGNING (منع تقطيع الإشارة)
        if (_currentMotion >= startThreshold) {
          _transitionTo(SignActivityState.signing, now);
          _signEndTime = null;
          _endReason = 'NONE';
        } else {
          // انتقال سريع ومباشر إلى READY لإطلاق التقييم
          _transitionTo(SignActivityState.ready, now);
        }
        break;

      case SignActivityState.ready:
        // حالة مؤقتة تنتهي بمجرد استهلاكها أو مرور وقت قصير
        final timeInReady = now.difference(_stateEnteredTime!).inMilliseconds;
        if (timeInReady > 400 || _currentMotion < startThreshold) {
          _transitionTo(SignActivityState.idle, now);
        }
        break;
    }

    return _buildDiagnostic(now);
  }

  /// حساب المسافة الإقليدية للنقاط الحقيقية فقط
  void _calculateFrameMotion({
    required IsharaBufferFrame current,
    required IsharaBufferFrame previous,
  }) {
    final curData = current.data;
    final prevData = previous.data;
    final curMeta = current.metadata;
    final prevMeta = previous.metadata;

    double rhDistSum = 0.0;
    int rhCount = 0;
    double lhDistSum = 0.0;
    int lhCount = 0;
    double lipsDistSum = 0.0;
    int lipsCount = 0;
    double bodyDistSum = 0.0;
    int bodyCount = 0;

    // Right Hand (نقاط 0..20) - تُحسب فقط إذا لم تكن معوضة في أي من الإطارين
    final bool rhValid =
        !curMeta.rightHandImputed &&
        !prevMeta.rightHandImputed &&
        curMeta.rightHandRawCount > 0;
    if (rhValid) {
      for (int i = 0; i < 21; i++) {
        final dx = curData[i * 2] - prevData[i * 2];
        final dy = curData[i * 2 + 1] - prevData[i * 2 + 1];
        rhDistSum += math.sqrt(dx * dx + dy * dy);
        rhCount++;
      }
    }

    // Left Hand (نقاط 21..41) - تُحسب فقط إذا لم تكن معوضة
    final bool lhValid =
        !curMeta.leftHandImputed &&
        !prevMeta.leftHandImputed &&
        curMeta.leftHandRawCount > 0;
    if (lhValid) {
      for (int i = 21; i < 42; i++) {
        final dx = curData[i * 2] - prevData[i * 2];
        final dy = curData[i * 2 + 1] - prevData[i * 2 + 1];
        lhDistSum += math.sqrt(dx * dx + dy * dy);
        lhCount++;
      }
    }

    // Lips (نقاط 42..60)
    final bool lipsValid =
        !curMeta.lipsImputed &&
        !prevMeta.lipsImputed &&
        curMeta.lipsRawCount > 0;
    if (lipsValid) {
      for (int i = 42; i < 61; i++) {
        final dx = curData[i * 2] - prevData[i * 2];
        final dy = curData[i * 2 + 1] - prevData[i * 2 + 1];
        lipsDistSum += math.sqrt(dx * dx + dy * dy);
        lipsCount++;
      }
    }

    // Body (نقاط 61..85)
    final bool bodyValid =
        !curMeta.bodyImputed &&
        !prevMeta.bodyImputed &&
        curMeta.bodyRawCount > 0;
    if (bodyValid) {
      for (int i = 61; i < 86; i++) {
        final dx = curData[i * 2] - prevData[i * 2];
        final dy = curData[i * 2 + 1] - prevData[i * 2 + 1];
        bodyDistSum += math.sqrt(dx * dx + dy * dy);
        bodyCount++;
      }
    }

    _rhMotion = rhCount > 0 ? rhDistSum / rhCount : 0.0;
    _lhMotion = lhCount > 0 ? lhDistSum / lhCount : 0.0;
    _lipsMotion = lipsCount > 0 ? lipsDistSum / lipsCount : 0.0;
    _bodyMotion = bodyCount > 0 ? bodyDistSum / bodyCount : 0.0;

    // الحركة الكلية المرجحة: الأيدي تأخذ الوزن الأكبر
    double weightedSum = 0.0;
    double totalWeight = 0.0;

    if (rhCount > 0) {
      weightedSum += _rhMotion * 1.5;
      totalWeight += 1.5;
    }
    if (lhCount > 0) {
      weightedSum += _lhMotion * 1.5;
      totalWeight += 1.5;
    }
    if (lipsCount > 0) {
      weightedSum += _lipsMotion * 0.4;
      totalWeight += 0.4;
    }
    if (bodyCount > 0) {
      weightedSum += _bodyMotion * 0.6;
      totalWeight += 0.6;
    }

    _currentMotion = totalWeight > 0 ? weightedSum / totalWeight : 0.0;
  }

  /// تحديث خط الأساس الحركي أثناء السكون
  void _updateBaseline(double motion) {
    if (motion > config.defaultStartThreshold * 1.5) return;

    _baselineBuffer.add(motion);
    if (_baselineBuffer.length > config.baselineWindowSize) {
      _baselineBuffer.removeAt(0);
    }

    if (_baselineBuffer.isNotEmpty) {
      final sum = _baselineBuffer.reduce((a, b) => a + b);
      _baselineMean = sum / _baselineBuffer.length;

      double varianceSum = 0.0;
      for (final val in _baselineBuffer) {
        final diff = val - _baselineMean;
        varianceSum += diff * diff;
      }
      _baselineStdDev = math.sqrt(varianceSum / _baselineBuffer.length);
    }
  }

  void _transitionTo(SignActivityState newState, DateTime time) {
    _state = newState;
    _stateEnteredTime = time;
  }

  /// إعادة تعيين الكاشف إلى وضع السكون
  void reset() {
    _state = SignActivityState.idle;
    _stateEnteredTime = null;
    _motionAboveStartTime = null;
    _motionBelowEndTime = null;
    _signStartTime = null;
    _signEndTime = null;
    _previousFrame = null;
    _endReason = 'NONE';
    _currentMotion = 0.0;
    _peakMotion = 0.0;
    _rhMotion = 0.0;
    _lhMotion = 0.0;
    _lipsMotion = 0.0;
    _bodyMotion = 0.0;
    _baselineBuffer.clear();
    _baselineMean = 0.008;
    _baselineStdDev = 0.003;
  }

  SignActivityDiagnostic _buildDiagnostic(DateTime now) {
    final duration = _stateEnteredTime != null
        ? now.difference(_stateEnteredTime!).inMilliseconds
        : 0;
    return SignActivityDiagnostic(
      state: _state,
      currentMotion: _currentMotion,
      baselineMean: _baselineMean,
      baselineStdDev: _baselineStdDev,
      startThreshold: dynamicStartThreshold,
      endThreshold: dynamicEndThreshold,
      rightHandMotion: _rhMotion,
      leftHandMotion: _lhMotion,
      lipsMotion: _lipsMotion,
      bodyMotion: _bodyMotion,
      stateDurationMs: duration,
      signSegmentId: _signSegmentId,
      endReason: _endReason,
    );
  }
}
