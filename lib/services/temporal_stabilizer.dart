import 'dart:collection';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/word_only_filter.dart';

enum SignStabilityState { detecting, candidate, stable }

/// مثبت الثبات الزمني المتكيف (Adaptive Temporal Stabilizer)
///
/// ينفذ المتطلبات:
/// 1. Adaptive Confidence: قبول ثقة أقل عند استقرار اليد وثقة أعلى عند التذبذب.
/// 2. Early Commit: اعتماد الكلمة فوراً عند ثباتها لعدة إطارات متتالية دون انتظار طويل.
/// 3. Temporal Majority Voting & Confidence Averaging داخل نافذة متكيفة (4 - 8 إطارات).
/// 4. Hysteresis: منع التبدل السريع بين الكلمات.
/// 5. Duplicate Suppression: منع تكرار نفس الكلمة المتتالية ما لم تتغير الإشارة أو تختفي اليد.
class TemporalStabilizer {
  static const String blankLabel = 'BLANK';

  final int minWindowSize;
  final int maxWindowSize;
  final double earlyExitConfidence;
  final double adoptConfidenceThreshold;
  final double adoptConfidenceThresholdStatic;
  final double retainConfidenceThreshold;
  final double minConfidenceThreshold;
  final Duration handResetTimeout;

  SignStabilityState _state = SignStabilityState.detecting;
  String? _candidateLabel;
  String? _lastEmittedStableLabel;
  double _lastConfidence = 0.0;
  DateTime? _lastDetectionTime;

  // طابور النافذة المتكيفة
  final Queue<SignPrediction?> _windowQueue = Queue<SignPrediction?>();
  int _currentAdaptiveWindowSize;
  int _consecutiveNullFrames = 0;

  // مؤشر مرور حالة الفراغ (BLANK) للسماح بتكرار نفس الكلمة لاحقاً
  bool _seenBlankSinceLastEmission = true;

  // ردود النداء
  void Function(SignPrediction stablePrediction)? onStableSign;
  void Function(SignStabilityState state, String? label, double confidence)? onStateChanged;

  TemporalStabilizer({
    this.minWindowSize = AppConstants.minTemporalWindow,
    this.maxWindowSize = AppConstants.maxTemporalWindow,
    this.earlyExitConfidence = AppConstants.earlyExitConfidence,
    this.adoptConfidenceThreshold = AppConstants.adoptConfidenceThreshold,
    this.adoptConfidenceThresholdStatic = AppConstants.adoptConfidenceThresholdStatic,
    this.retainConfidenceThreshold = AppConstants.retainConfidenceThreshold,
    this.minConfidenceThreshold = AppConstants.minConfidence,
    this.handResetTimeout = const Duration(milliseconds: 800),
  }) : _currentAdaptiveWindowSize = AppConstants.minTemporalWindow;

  SignStabilityState get state => _state;
  String? get candidateLabel => _candidateLabel;
  String? get lastStableLabel => _lastEmittedStableLabel;
  double get lastConfidence => _lastConfidence;
  int get currentWindowSize => _currentAdaptiveWindowSize;

  /// معالجة تنبؤ إطار قادم من محرك التعرف مع الأخذ بالحسبان استقرار الحركة وحدود الإشارة
  void processPrediction(
    SignPrediction? prediction, {
    bool isHandStatic = false,
    bool isSignBoundary = false,
  }) {
    final now = DateTime.now();

    // 1. فحص انقطاع اليد أو انقضاء المهلة
    if (_lastDetectionTime != null && now.difference(_lastDetectionTime!) > handResetTimeout) {
      _handleBlankState();
    }

    // 2. تصفية التنبؤ: التحقق من بوابة الثقة واستبعاد الأحرف المنفردة عبر WordOnlyFilter
    SignPrediction? effectivePrediction;
    if (prediction != null &&
        prediction.confidence >= retainConfidenceThreshold &&
        WordOnlyFilter.isValidWord(prediction.label)) {
      effectivePrediction = prediction;
      _lastDetectionTime = now;
      _lastConfidence = prediction.confidence;
      _consecutiveNullFrames = 0;
    } else {
      effectivePrediction = null;
      _consecutiveNullFrames++;
    }

    // إضافة الإطار للنافذة الزمنية
    _windowQueue.addLast(effectivePrediction);
    while (_windowQueue.length > _currentAdaptiveWindowSize) {
      _windowQueue.removeFirst();
    }

    // إذا توالت الإطارات الفارغة لـ 3 مرات أو أكثر ➔ حالة فراغ
    if (_consecutiveNullFrames >= 3) {
      _handleBlankState();
      return;
    }

    // إذا كان الإطار الحالي فقط فارغاً بصورة عابرة، لا نلغي الأصوات المتراكمة
    if (effectivePrediction == null) {
      return;
    }

    // 3. Early Commit (الاعتماد المبكر السريع):
    // إذا ظهرت نفس الكلمة في آخر 3 إطارات متتالية بثقة مقبولة، أو آخر إطارين مع Sign Boundary
    final recentPredictions = _windowQueue.whereType<SignPrediction>().toList();
    if (recentPredictions.length >= 3) {
      final last3 = recentPredictions.sublist(recentPredictions.length - 3);
      final word0 = last3[0].label.trim();
      final allSame = last3.every((p) => p.label.trim() == word0);
      final avgConf3 = (last3[0].confidence + last3[1].confidence + last3[2].confidence) / 3.0;

      if (allSame && (avgConf3 >= earlyExitConfidence || (isHandStatic && avgConf3 >= adoptConfidenceThresholdStatic))) {
        _commitStableSign(last3.last, avgConf3);
        return;
      }
    } else if (isSignBoundary && recentPredictions.length >= 2) {
      final last2 = recentPredictions.sublist(recentPredictions.length - 2);
      final word0 = last2[0].label.trim();
      if (last2[1].label.trim() == word0) {
        final avgConf2 = (last2[0].confidence + last2[1].confidence) / 2.0;
        if (avgConf2 >= adoptConfidenceThresholdStatic) {
          _commitStableSign(last2.last, avgConf2);
          return;
        }
      }
    }

    // 4. التصويت الأغلبي الزمني (Temporal Majority Voting)
    final labelVotes = <String, int>{};
    final labelConfidenceSums = <String, double>{};
    final labelPredictions = <String, SignPrediction>{};

    for (final p in _windowQueue) {
      if (p != null) {
        final lbl = p.label.trim();
        labelVotes[lbl] = (labelVotes[lbl] ?? 0) + 1;
        labelConfidenceSums[lbl] = (labelConfidenceSums[lbl] ?? 0.0) + p.confidence;
        labelPredictions[lbl] = p;
      }
    }

    if (labelVotes.isEmpty) {
      _handleBlankState();
      return;
    }

    // العثور على الكلمة صاحبة أعلى الأصوات
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

    // 5. نظام الثقة المتكيفة (Adaptive Confidence Threshold):
    // إذا كانت اليد مستقرة (isHandStatic) نقبل ثقة أقل، وإذا كانت متذبذبة نطلب ثقة أعلى
    final bool isSameAsCandidate = bestLabel == _candidateLabel;
    final double requiredThreshold = isSameAsCandidate
        ? retainConfidenceThreshold
        : (isHandStatic ? adoptConfidenceThresholdStatic : adoptConfidenceThreshold);

    if (avgConfidence < requiredThreshold) {
      if (_state != SignStabilityState.detecting) {
        _state = SignStabilityState.detecting;
        _notifyState();
      }
      return;
    }

    // تحديث المرشح
    _candidateLabel = bestLabel;
    _lastConfidence = avgConfidence;

    // 6. التحقق من ثبات الكلمة
    final bool hasConsensus = maxVotes >= 2 &&
        (avgConfidence >= requiredThreshold || isSignBoundary || isHandStatic);

    if (hasConsensus) {
      _commitStableSign(labelPredictions[bestLabel]!, avgConfidence);
    } else {
      if (_state != SignStabilityState.candidate) {
        _state = SignStabilityState.candidate;
        _notifyState();
      }
    }
  }

  /// اعتماد كلمة مستقرة مع منع التكرار المباشر لنفس الإشارة
  void _commitStableSign(SignPrediction prediction, double confidence) {
    final word = prediction.label.trim();

    if (_state != SignStabilityState.stable) {
      _state = SignStabilityState.stable;
      _candidateLabel = word;
      _lastConfidence = confidence;
      _notifyState();
    }

    // منع التكرار (Duplicate Suppression):
    // لا نسمح بإضافة نفس الكلمة إلا إذا مرت حالة فراغ (اختفاء يد / توقف) أو تغيرت الإشارة
    if (_lastEmittedStableLabel != word || _seenBlankSinceLastEmission) {
      _lastEmittedStableLabel = word;
      _seenBlankSinceLastEmission = false;

      final stablePred = prediction.copyWith(confidence: confidence);

      if (onStableSign != null) {
        onStableSign!(stablePred);
      }

      // تفريغ جزئي للنافذة لبدء الإشارة التالية بسلاسة
      _windowQueue.clear();
      _currentAdaptiveWindowSize = minWindowSize;
    }
  }

  void _handleBlankState() {
    _seenBlankSinceLastEmission = true;
    _candidateLabel = null;
    _consecutiveNullFrames = 0;
    if (_state != SignStabilityState.detecting) {
      _state = SignStabilityState.detecting;
      _notifyState();
    }
  }

  void _notifyState() {
    if (onStateChanged != null) {
      onStateChanged!(_state, _candidateLabel, _lastConfidence);
    }
  }

  /// إتاحة اعتماد الكلمة نفسها مرة أخرى عند بدء حركة جديدة
  void allowNextSignAfterMotion() {
    _seenBlankSinceLastEmission = true;
  }

  /// مسح الذاكرة الحالية بالكامل
  void reset() {
    _windowQueue.clear();
    _currentAdaptiveWindowSize = minWindowSize;
    _candidateLabel = null;
    _lastEmittedStableLabel = null;
    _seenBlankSinceLastEmission = true;
    _consecutiveNullFrames = 0;
    _state = SignStabilityState.detecting;
    _lastDetectionTime = null;
  }
}
