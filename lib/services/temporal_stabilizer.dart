import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:ishara/constants/sign_recognition_config.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/motion_analyzer.dart';
import 'package:ishara/services/sign_rejection_layer.dart';
import 'package:ishara/services/word_only_filter.dart';

/// الحالات الخمس لآلة الحالة الزمنية (Temporal State Machine)
/// IDLE → SIGNING → CANDIDATE_STABLE → COMMITTED → COOLDOWN → IDLE
enum SignStabilityState {
  idle,           // سكون: لا حركة كافية، لا قرار
  signing,        // حركة نشطة: جمع الإطارات في نافذة منزلقة، لا إصدار لقرار بعد
  candidateStable,// ثبات المرشح: نفس التصنيف تكرر بثبات عبر عدة إطارات (Majority Voting + Hysteresis)
  committed,      // اعتماد: يُعتمد الكلمة لمرة واحدة فقط وتُرسل للـ Gloss Buffer
  cooldown;       // تبريد: فترة تبريد إلزامية لا يُقبل خلالها نفس التصنيف مرة أخرى

  // أسماء مرادفة للتوافقية مع الشيفرات السابقة
  static const SignStabilityState detecting = SignStabilityState.idle;
  static const SignStabilityState candidate = SignStabilityState.candidateStable;
  static const SignStabilityState stable = SignStabilityState.committed;

  bool get isIdleState => this == SignStabilityState.idle;
  bool get isSigningState => this == SignStabilityState.signing;
  bool get isStableState => this == SignStabilityState.committed || this == SignStabilityState.candidateStable;
  bool get isCooldownState => this == SignStabilityState.cooldown;

  String get arabicLabel {
    switch (this) {
      case SignStabilityState.idle:
        return 'سكون (IDLE)';
      case SignStabilityState.signing:
        return 'جارٍ التوقيع (SIGNING)';
      case SignStabilityState.candidateStable:
        return 'مرشح مستقر';
      case SignStabilityState.committed:
        return 'معتمدة (COMMITTED)';
      case SignStabilityState.cooldown:
        return 'فترة تبريد (COOLDOWN)';
    }
  }
}

/// آلة الحالة الزمنية المتكاملة لتمييز لغة الإشارة (Temporal State Machine)
///
/// تطبق دورة الحياة الكاملة:
/// 1. IDLE: إهمال أي إشارات عند سكون اليد مهما كانت ثقة الموديل (حل مشكلة السلام التلقائية).
/// 2. SIGNING: تجميع الإطارات في نافذة منزلقة (Sliding Window: 8 - 12 إطار) عند وجود حركة فعلية.
/// 3. CANDIDATE_STABLE: تصويت أغلبي زمني (Majority Voting) مع متوسط الثقة و Hysteresis.
/// 4. COMMITTED: اعتماد الكلمة مرة واحدة فقط وإرسالها للـ Gloss Buffer.
/// 5. COOLDOWN: فترة تبريد إلزامية تمنع تكرار نفس الكلمة حتى لو بقيت اليد ثابتة، ولا تُكسر
///    إلا بسكون تام (IDLE) أو قفزة حركة واضحة (Motion Spike).
class TemporalStabilizer {
  final int windowSize;
  final double majorityVoteRatio;
  final int cooldownFrames;
  final double earlyExitConfidence;
  final double motionSpikeBreakThreshold;
  final double motionEnergyBreakThreshold;
  final Duration handResetTimeout;

  final SignRejectionLayer _rejectionLayer;

  SignStabilityState _state = SignStabilityState.idle;
  String? _candidateLabel;
  String? _lastCommittedLabel;
  double _lastConfidence = 0.0;
  DateTime? _lastActiveTime;

  // طابور النافذة الزمنية المنزلقة
  final Queue<SignPrediction?> _windowQueue = Queue<SignPrediction?>();
  int _consecutiveIdleFrames = 0;
  int _cooldownFramesElapsed = 0;
  int _stableFramesCount = 0;

  // مؤشر مرور حالة فراغ أو حركة جديدة تتيح تكرار الكلمة لاحقاً
  bool _canCommitSameWordAgain = true;

  // ردود النداء (Callbacks)
  void Function(SignPrediction stablePrediction)? onStableSign;
  void Function(SignStabilityState state, String? label, double confidence)? onStateChanged;

  TemporalStabilizer({
    this.windowSize = SignRecognitionConfig.stableWindowSize,
    this.majorityVoteRatio = SignRecognitionConfig.majorityVoteRatio,
    this.cooldownFrames = SignRecognitionConfig.cooldownFrames,
    this.earlyExitConfidence = SignRecognitionConfig.earlyExitConfidence,
    this.motionSpikeBreakThreshold = SignRecognitionConfig.motionSpikeBreakThreshold,
    this.motionEnergyBreakThreshold = SignRecognitionConfig.motionEnergyBreakThreshold,
    this.handResetTimeout = const Duration(milliseconds: SignRecognitionConfig.handResetTimeoutMs),
    double minConfidenceThreshold = SignRecognitionConfig.minConfidence,
    double confidenceMargin = SignRecognitionConfig.confidenceMargin,
    double minMotionEnergy = SignRecognitionConfig.minMotionEnergy,
    double minVelocity = SignRecognitionConfig.minVelocity,
    int? minWindowSize,
    int? maxWindowSize,
    double? adoptConfidenceThreshold,
    double? adoptConfidenceThresholdStatic,
    double? retainConfidenceThreshold,
  }) : _rejectionLayer = SignRejectionLayer(
         minConfidence: minConfidenceThreshold,
         confidenceMargin: confidenceMargin,
         minMotionEnergy: minMotionEnergy,
         minVelocity: minVelocity,
       );

  SignStabilityState get state => _state;
  String? get candidateLabel => _candidateLabel;
  String? get lastStableLabel => _lastCommittedLabel;
  double get lastConfidence => _lastConfidence;
  int get currentWindowQueueLength => _windowQueue.length;

  /// معالجة تنبؤ إطار قادم مع معالم الحركة وربطها بطبقة الرفض
  void processPrediction(
    SignPrediction? prediction, {
    MotionFeatures? motion,
    bool isHandStatic = false,
    bool isSignBoundary = false,
  }) {
    final now = DateTime.now();

    // 1. فحص مهلة انقطاع اليد
    if (_lastActiveTime != null && now.difference(_lastActiveTime!) > handResetTimeout) {
      _handleResetToIdle();
    }

    // بناء كائن الحركة إذا لم يُمرر
    final effMotion = motion ?? (isHandStatic
        ? MotionFeatures.staticInitial()
        : MotionFeatures(
            averageVelocity: 0.05,
            wristVelocity: 0.05,
            directionX: 0,
            directionY: 0,
            directionZ: 0,
            motionEnergy: 0.03,
            angularVelocity: 0,
            distanceRate: 0,
            isHandStatic: false,
            isSignBoundary: isSignBoundary,
          ));

    // 2. فحص طبقة الرفض الموحدة (Rejection Layer)
    final evaluation = _rejectionLayer.evaluate(
      prediction: prediction,
      motion: effMotion,
    );

    // ──────────────────────── حالة السكون (IDLE / NO_SIGN) ────────────────────────
    if (evaluation.isIdle) {
      _consecutiveIdleFrames++;

      if (_state == SignStabilityState.cooldown) {
        _cooldownFramesElapsed++;
        // إذا سكنت اليد 3 إطارات أثناء الـ Cooldown أو انقضت مدته -> الخروج إلى IDLE
        if (_consecutiveIdleFrames >= 3 || _cooldownFramesElapsed >= cooldownFrames) {
          _canCommitSameWordAgain = true;
          _transitionTo(SignStabilityState.idle);
        }
        return;
      }

      if (_state == SignStabilityState.signing || _state == SignStabilityState.candidateStable) {
        // توقفت الحركة دون الوصول لثبات مؤكد
        if (_consecutiveIdleFrames >= 4) {
          _handleResetToIdle();
        }
        return;
      }

      // إذا كانت بالفعل IDLE
      if (_state != SignStabilityState.idle && _state != SignStabilityState.detecting) {
        _transitionTo(SignStabilityState.idle);
      }
      return;
    }

    // ──────────────────────── حركة نشطة (Active Motion) ────────────────────────
    _consecutiveIdleFrames = 0;
    _lastActiveTime = now;

    // 3. إدارة حالة التبريد (COOLDOWN Management)
    if (_state == SignStabilityState.cooldown) {
      _cooldownFramesElapsed++;

      // فحص كسر الـ Cooldown بقفزة حركة واضحة (Motion Spike)
      final bool isMotionSpike = effMotion.averageVelocity >= motionSpikeBreakThreshold ||
          effMotion.motionEnergy >= motionEnergyBreakThreshold;

      if (isMotionSpike) {
        if (kDebugMode) {
          debugPrint('[TemporalStabilizer] Cooldown broken by motion spike: vel=${effMotion.averageVelocity.toStringAsFixed(3)}');
        }
        _canCommitSameWordAgain = true;
        _windowQueue.clear();
        _transitionTo(SignStabilityState.signing);
      } else if (_cooldownFramesElapsed >= cooldownFrames) {
        // انقضاء فترة التبريد المحددة
        _canCommitSameWordAgain = true;
        _transitionTo(SignStabilityState.signing);
      } else {
        // لا نزال في فترة التبريد: منع التكرار قطيعاً حتى لو استمرت اليد في نفس الوضعية!
        return;
      }
    }

    // 4. الانتقال من IDLE إلى SIGNING عند بدء حركة مقبولة
    if (_state == SignStabilityState.idle || _state == SignStabilityState.detecting) {
      _windowQueue.clear();
      _transitionTo(SignStabilityState.signing);
    }

    // 5. إضافة الإطار المقبول للنافذة المنزلقة (Sliding Window)
    if (evaluation.isAccepted && evaluation.prediction != null) {
      _windowQueue.addLast(evaluation.prediction!);
    } else {
      _windowQueue.addLast(null);
    }

    while (_windowQueue.length > windowSize) {
      _windowQueue.removeFirst();
    }

    // 6. فحص الاعتماد السريع (Early Exit) لإشارات واضحة وثابتة عبر 3 إطارات متتالية
    final nonNullRecent = _windowQueue.whereType<SignPrediction>().toList();
    if (nonNullRecent.length >= 3) {
      final last3 = nonNullRecent.sublist(nonNullRecent.length - 3);
      final word0 = last3[0].label.trim();
      final allSame = last3.every((p) => p.label.trim() == word0);
      final avgConf3 = (last3[0].confidence + last3[1].confidence + last3[2].confidence) / 3.0;

      if (allSame && avgConf3 >= earlyExitConfidence) {
        _tryCommitSign(last3.last, avgConf3);
        return;
      }
    }

    // 7. التصويت الأغلبي الزمني وتوسط الثقة (Majority Voting & Confidence Averaging)
    final labelVotes = <String, int>{};
    final labelConfidenceSums = <String, double>{};
    final labelPredictions = <String, SignPrediction>{};

    for (final p in _windowQueue) {
      if (p != null && WordOnlyFilter.isValidWord(p.label)) {
        final lbl = p.label.trim();
        labelVotes[lbl] = (labelVotes[lbl] ?? 0) + 1;
        labelConfidenceSums[lbl] = (labelConfidenceSums[lbl] ?? 0.0) + p.confidence;
        labelPredictions[lbl] = p;
      }
    }

    if (labelVotes.isEmpty) {
      return;
    }

    String bestLabel = '';
    int maxVotes = 0;
    double avgConfidence = 0.0;

    for (final entry in labelVotes.entries) {
      if (entry.value > maxVotes) {
        maxVotes = entry.value;
        bestLabel = entry.key;
        avgConfidence = labelConfidenceSums[bestLabel]! / entry.value;
      }
    }

    final totalWindowCount = _windowQueue.length;
    final voteRatio = totalWindowCount > 0 ? (maxVotes / totalWindowCount) : 0.0;

    // 8. Hysteresis: لا ننتقل لمرشح جديد إلا إذا تفوق بنسبة أصوات واضحة
    final bool passesHysteresis = _candidateLabel == null ||
        _candidateLabel == bestLabel ||
        maxVotes >= 3;

    final bool hasConsensus = maxVotes >= 2 &&
        voteRatio >= (majorityVoteRatio * 0.8) &&
        avgConfidence >= _rejectionLayer.minConfidence &&
        passesHysteresis;

    if (hasConsensus) {
      _candidateLabel = bestLabel;
      _lastConfidence = avgConfidence;

      if (_state == SignStabilityState.signing || _state == SignStabilityState.candidate) {
        _transitionTo(SignStabilityState.candidateStable);
        _stableFramesCount = 1;
      } else if (_state == SignStabilityState.candidateStable) {
        _stableFramesCount++;
        // إذا استقر المرشح لعدة إطارات متتالية أو حاز غالبية قوية
        if (_stableFramesCount >= 2 || voteRatio >= majorityVoteRatio) {
          _tryCommitSign(labelPredictions[bestLabel]!, avgConfidence);
        }
      }
    } else {
      if (_state == SignStabilityState.candidateStable) {
        _transitionTo(SignStabilityState.signing);
        _stableFramesCount = 0;
      }
    }
  }

  /// محاولة اعتماد الإشارة (COMMITTED) مع فحص التكرار
  void _tryCommitSign(SignPrediction prediction, double confidence) {
    final word = prediction.label.trim();

    // منع التكرار المتصل (Duplicate Suppression):
    // إذا كانت نفس الكلمة السابقة ولم تمر حالة فراغ حقيقية أو قفزة حركة، نمنع تكرارها
    if (_lastCommittedLabel == word && !_canCommitSameWordAgain) {
      if (kDebugMode) {
        debugPrint('[TemporalStabilizer] Suppressed repeating word: "$word"');
      }
      return;
    }

    _lastCommittedLabel = word;
    _canCommitSameWordAgain = false;
    _candidateLabel = word;
    _lastConfidence = confidence;

    // 1. الانتقال لحالة COMMITTED
    _transitionTo(SignStabilityState.committed);

    final stablePred = prediction.copyWith(confidence: confidence);
    if (onStableSign != null) {
      onStableSign!(stablePred);
    }

    // 2. الدخول فوراً في فترة التبريد الإلزامية (COOLDOWN)
    _cooldownFramesElapsed = 0;
    _windowQueue.clear();
    _transitionTo(SignStabilityState.cooldown);
  }

  void _transitionTo(SignStabilityState newState) {
    _state = newState;
    if (onStateChanged != null) {
      onStateChanged!(_state, _candidateLabel, _lastConfidence);
    }
  }

  void _handleResetToIdle() {
    _canCommitSameWordAgain = true;
    _candidateLabel = null;
    _windowQueue.clear();
    _consecutiveIdleFrames = 0;
    _stableFramesCount = 0;
    _transitionTo(SignStabilityState.idle);
  }

  /// إتاحة اعتماد الكلمة نفسها مجدداً عند رصد حركة جديدة واضحة
  void allowNextSignAfterMotion() {
    _canCommitSameWordAgain = true;
  }

  /// تفريغ الذاكرة بالكامل
  void reset() {
    _windowQueue.clear();
    _candidateLabel = null;
    _lastCommittedLabel = null;
    _canCommitSameWordAgain = true;
    _consecutiveIdleFrames = 0;
    _cooldownFramesElapsed = 0;
    _stableFramesCount = 0;
    _lastActiveTime = null;
    _transitionTo(SignStabilityState.idle);
  }
}
