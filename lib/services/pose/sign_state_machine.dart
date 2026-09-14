import 'package:ishara/models/sign_segment.dart';
import 'package:ishara/services/pose/sign_presence_validator.dart';
import 'package:ishara/services/pose/temporal_motion_analyzer.dart';

/// حالات آلة الحالة الزمنية لتمييز الإشارة (SignTemporalState)
enum SignTemporalState {
  waitingForPerson,
  waitingForHand,
  ready,
  signStarting,
  signActive,
  signEnding,
  analyzing,
  candidate,
  confirmed,
  cooldown;

  String get arabicLabel {
    switch (this) {
      case SignTemporalState.waitingForPerson:
        return 'بانتظار ظهور الشخص';
      case SignTemporalState.waitingForHand:
        return 'بانتظار ظهور اليد';
      case SignTemporalState.ready:
        return 'جاهز لبدء الإشارة';
      case SignTemporalState.signStarting:
        return 'بداية حركة الإشارة';
      case SignTemporalState.signActive:
        return 'حركة الإشارة مستمرة';
      case SignTemporalState.signEnding:
        return 'انتهاء حركة الإشارة';
      case SignTemporalState.analyzing:
        return 'جارٍ تحليل الإشارة...';
      case SignTemporalState.candidate:
        return 'تقييم النتيجة';
      case SignTemporalState.confirmed:
        return 'تم تأكيد الإشارة';
      case SignTemporalState.cooldown:
        return 'فترة تهدئة';
    }
  }
}

/// آلة الحالة الزمنية لتقطيع ودورة حياة الإشارة (SignStateMachine)
///
/// تطبق بدقة المتطلبات:
/// 1. لا ترجمة بدون Head/Face + Hand
/// 2. لا ترجمة أثناء SIGN_ACTIVE (تجميع فقط)
/// 3. تحليل الحركة فقط بعد استقرارها في SIGN_ENDING -> ANALYZING
/// 4. التحقق من الحد الأدنى والأقصى لمدّة الإشارة (Minimum & Maximum Sign Duration)
/// 5. التحقق من نسبة المعالم الصالحة (Valid Landmark Ratio)
/// 6. فترة التهدئة وحظر تكرار نفس الكلمة قبل الانتقال لحالة Neutral/Transition
class SignStateMachine {
  final List<void Function()> _listeners = [];

  void addListener(void Function() listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void notifyListeners() {
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
  }

  SignTemporalState _state = SignTemporalState.waitingForPerson;

  // إعدادات قابلة للمعايرة
  int startFramesThreshold;
  int endingFramesThreshold;
  int minimumSignFrames;
  int maximumSignFrames;
  double minValidHandRatio;
  double minValidHeadRatio;
  Duration cooldownDuration;

  // عدادات الحالات المتتالية
  int _startMotionStreak = 0;
  int _settledMotionStreak = 0;
  int _missingHandStreak = 0;
  int _missingHeadStreak = 0;
  int _globalFrameIndex = 0;
  int _signStartFrameIndex = 0;

  // مخزن تجميع الإطارات للإشارة الحالية
  final List<List<List<double>>> _activeSignFrames = [];
  int _validHandCount = 0;
  int _validHeadCount = 0;
  int _validFaceCount = 0;
  final List<double> _accumulatedEnergies = [];

  // آخر إشارة مكتملة جاهزة للتحليل
  SignSegment? _completedSegment;
  String? _lastConfirmedWord;
  DateTime? _lastConfirmedTime;

  SignStateMachine({
    this.startFramesThreshold = 3,
    this.endingFramesThreshold = 6,
    this.minimumSignFrames = 14,
    this.maximumSignFrames = 128,
    this.minValidHandRatio = 0.55,
    this.minValidHeadRatio = 0.55,
    this.cooldownDuration = const Duration(milliseconds: 750),
  });

  SignTemporalState get state => _state;
  SignSegment? get completedSegment => _completedSegment;
  int get activeFramesCount => _activeSignFrames.length;
  String? get lastConfirmedWord => _lastConfirmedWord;

  /// معالجة إطار جديد وتحديث آلة الحالة
  SignTemporalState processFrame({
    required FramePresenceResult presence,
    required TemporalMotionResult motion,
    required List<List<double>> frame86x2,
    List<List<List<double>>>? preRollFrames,
  }) {
    _globalFrameIndex++;

    // ──────────────── 1. التحقق الصارم من حضور الشخص أولاً ثم اليد (المتطلب 1 و 2 و 4) ────────────────
    if (!presence.personPresent) {
      _missingHeadStreak++;
      if (_state == SignTemporalState.signActive && _missingHeadStreak <= 3) {
        // سماح بتذبذب عابر قصير جداً للشخص
      } else {
        _transitionTo(SignTemporalState.waitingForPerson);
        _abortCurrentSign();
        return _state;
      }
    } else {
      _missingHeadStreak = 0;
    }

    if (!presence.hasAtLeastOneHand) {
      _missingHandStreak++;
      if (_state == SignTemporalState.signActive && _missingHandStreak <= 2) {
        // المتطلب 22: لا نمسح Sign بسبب فقدان Hand لإطار واحد عابر
      } else {
        if (_state == SignTemporalState.signActive &&
            _activeSignFrames.length >= minimumSignFrames) {
          // إذا كانت اليد تتحرك ثم خرجت من الكادر بعد إشارة كاملة
          _closeSegmentAndAnalyze();
          return _state;
        } else {
          _transitionTo(SignTemporalState.waitingForHand);
          _abortCurrentSign();
          return _state;
        }
      }
    } else {
      _missingHandStreak = 0;
    }

    // ──────────────── 2. إدارة آلة الحالة حسب الحالة الراهنة ────────────────
    switch (_state) {
      case SignTemporalState.waitingForPerson:
      case SignTemporalState.waitingForHand:
        if (presence.isSignEligible) {
          _transitionTo(SignTemporalState.ready);
        }
        break;

      case SignTemporalState.cooldown:
        final now = DateTime.now();
        final bool cooldownExpired = _lastConfirmedTime != null &&
            now.difference(_lastConfirmedTime!) > cooldownDuration;
        // الانتقال للـ READY عند سكون اليد وانتهاء مهلة التهدئة
        if (cooldownExpired || motion.isBelowEndThreshold) {
          _transitionTo(SignTemporalState.ready);
        }
        break;

      case SignTemporalState.ready:
        // فحص بداية حركة الإشارة (المتطلب 7)
        if (motion.isAboveStartThreshold) {
          _startMotionStreak++;
          if (_startMotionStreak >= startFramesThreshold) {
            // بدأت الإشارة رسمياً: نضم إطارات الـ Pre-roll (المتطلب 12)
            _startMotionStreak = 0;
            _settledMotionStreak = 0;
            _signStartFrameIndex = _globalFrameIndex;
            _activeSignFrames.clear();
            _accumulatedEnergies.clear();
            _validHandCount = 0;
            _validHeadCount = 0;
            _validFaceCount = 0;

            if (preRollFrames != null && preRollFrames.isNotEmpty) {
              for (final prFrame in preRollFrames) {
                _activeSignFrames.add(List.generate(
                  prFrame.length,
                  (i) => List<double>.from(prFrame[i]),
                ));
              }
            }

            _transitionTo(SignTemporalState.signStarting);
          }
        } else {
          _startMotionStreak = 0;
        }
        break;

      case SignTemporalState.signStarting:
        // الانتقال السلس للحركة النشطة
        _appendCurrentFrame(frame86x2, presence, motion.motionEnergy);
        _transitionTo(SignTemporalState.signActive);
        break;

      case SignTemporalState.signActive:
        // المتطلب 8: أثناء SIGN_ACTIVE لا نعرض أي كلمة، نجمع الإطارات فقط!
        _appendCurrentFrame(frame86x2, presence, motion.motionEnergy);

        // فحص تجاوز الحد الأقصى للإشارة (المتطلب 11)
        if (_activeSignFrames.length >= maximumSignFrames) {
          _closeSegmentAndAnalyze();
          break;
        }

        // فحص بداية استقرار الإشارة (تباطؤ الحركة)
        if (motion.isBelowEndThreshold) {
          _settledMotionStreak++;
          // الانتقال لمرحلة نهاية الإشارة بعد استقرار مبدئي (نصف المهلة أو إطارين)
          if (_settledMotionStreak >= (endingFramesThreshold ~/ 2).clamp(1, 3)) {
            _transitionTo(SignTemporalState.signEnding);
          }
        } else {
          _settledMotionStreak = 0;
        }
        break;

      case SignTemporalState.signEnding:
        _appendCurrentFrame(frame86x2, presence, motion.motionEnergy);

        // فحص تجاوز الحد الأقصى للإشارة
        if (_activeSignFrames.length >= maximumSignFrames) {
          _closeSegmentAndAnalyze();
          break;
        }

        if (motion.isBelowEndThreshold) {
          _settledMotionStreak++;
          if (_settledMotionStreak >= endingFramesThreshold) {
            // استقرت الحركة بالكامل: إغلاق الشريحة والانتقال للتحليل (ANALYZING)
            _closeSegmentAndAnalyze();
          }
        } else if (motion.isAboveActiveThreshold) {
          // استئناف الحركة النشطة دون توقف كامل
          _settledMotionStreak = 0;
          _transitionTo(SignTemporalState.signActive);
        }
        break;

      case SignTemporalState.analyzing:
      case SignTemporalState.candidate:
      case SignTemporalState.confirmed:
        // تدار هذه الحالات خارجياً عبر الـ Recognition Provider بعد اكتمال الاستنتاج
        break;
    }

    return _state;
  }

  /// إلحاق إطار بالمخزن الحالي وتحديث إحصائيات الحضور
  void _appendCurrentFrame(
    List<List<double>> frame86x2,
    FramePresenceResult presence,
    double energy,
  ) {
    _activeSignFrames.add(List.generate(
      frame86x2.length,
      (i) => List<double>.from(frame86x2[i]),
    ));
    if (presence.hasAtLeastOneHand) _validHandCount++;
    if (presence.headPresent) _validHeadCount++;
    if (presence.facePresent) _validFaceCount++;
    _accumulatedEnergies.add(energy);
  }

  /// إغلاق الشريحة والتحقق من الشروط قبل الانتقال للـ ANALYZING
  void _closeSegmentAndAnalyze() {
    final int totalFrames = _activeSignFrames.length;

    // المتطلب 10: الحد الأدنى لعدد الإطارات (أقصر = Noise ورفض فوري)
    if (totalFrames < minimumSignFrames) {
      _abortCurrentSign();
      _transitionTo(SignTemporalState.ready);
      return;
    }

    final double validHandRatio = _validHandCount / totalFrames;
    final double validHeadRatio = _validHeadCount / totalFrames;
    final double validFaceRatio = _validFaceCount / totalFrames;

    // المتطلب 21: رفض إذا فُقدت اليد أو الرأس في نسبة كبيرة
    if (validHandRatio < minValidHandRatio || validHeadRatio < minValidHeadRatio) {
      _abortCurrentSign();
      _transitionTo(SignTemporalState.ready);
      return;
    }

    final double avgEnergy = _accumulatedEnergies.isNotEmpty
        ? _accumulatedEnergies.reduce((a, b) => a + b) / _accumulatedEnergies.length
        : 0.0;

    _completedSegment = SignSegment(
      startFrame: _signStartFrameIndex,
      endFrame: _globalFrameIndex,
      durationFrames: totalFrames,
      frames: List.from(_activeSignFrames),
      validHandRatio: validHandRatio,
      validHeadRatio: validHeadRatio,
      validFaceRatio: validFaceRatio,
      averageMotionEnergy: avgEnergy,
    );

    _transitionTo(SignTemporalState.analyzing);
  }

  /// إشعار بتسجيل نتيجة Candidate محتملة من الموديل
  void markCandidate(String word, double confidence) {
    if (_state == SignTemporalState.analyzing) {
      _transitionTo(SignTemporalState.candidate);
    }
  }

  /// إشعار باعتماد الإشارة رسمياً (CONFIRMED) بعد اجتياز كل طبقات الفحص
  void confirmSign(String word) {
    _lastConfirmedWord = word;
    _lastConfirmedTime = DateTime.now();
    _transitionTo(SignTemporalState.confirmed);
    _activeSignFrames.clear();
  }

  /// بدء فترة التهدئة بعد الإشارة المؤكدة
  void startCooldown() {
    _transitionTo(SignTemporalState.cooldown);
    _completedSegment = null;
  }

  /// إلغاء الإشارة الحالية وتفريغ الذاكرة المؤقتة
  void _abortCurrentSign() {
    _activeSignFrames.clear();
    _accumulatedEnergies.clear();
    _startMotionStreak = 0;
    _settledMotionStreak = 0;
    _validHandCount = 0;
    _validHeadCount = 0;
    _validFaceCount = 0;
    _completedSegment = null;
  }

  void reset() {
    _abortCurrentSign();
    _lastConfirmedWord = null;
    _lastConfirmedTime = null;
    _state = SignTemporalState.waitingForPerson;
    notifyListeners();
  }

  void _transitionTo(SignTemporalState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  void dispose() {
    _listeners.clear();
  }
}
