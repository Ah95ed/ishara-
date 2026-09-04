import 'dart:collection';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/word_only_filter.dart';

enum SignStabilityState { detecting, candidate, stable }

/// مثبت الثبات الزمني المتقدم (Adaptive Temporal Stabilizer)
///
/// ينفذ المتطلبات:
/// 2. Adaptive Temporal Window: نافذة متكيفة من 8 إلى 24 إطاراً مع Early Exit.
/// 5. Temporal Majority Voting: تصويت الأغلبية المرجح بالثقة داخل النافذة.
/// 6. Hysteresis: عتبة اعتماد جديدة (0.82) أعلى من عتبة الاحتفاظ (0.60).
/// 7. CTC-like Collapse: حالة BLANK مدمجة لتقليص التكرارات.
/// 9. Duplicate Suppression: منع تكرار نفس الكلمة طالما الإشارة مستمرة دون BLANK.
/// 11. Confidence Gate: عدم التخمين وإبقاء الحالة Detecting/Unknown إذا كانت الثقة غير كافية.
/// 12. Early Exit: إنهاء التحليل مبكراً عند ثبات الكلمة بوضوح.
class TemporalStabilizer {
  static const String blankLabel = 'BLANK';

  final int minWindowSize;
  final int maxWindowSize;
  final double earlyExitConfidence;
  final double adoptConfidenceThreshold;
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
    this.retainConfidenceThreshold = AppConstants.retainConfidenceThreshold,
    this.minConfidenceThreshold = AppConstants.minConfidence,
    this.handResetTimeout = const Duration(milliseconds: 1200),
  }) : _currentAdaptiveWindowSize = AppConstants.minTemporalWindow;

  SignStabilityState get state => _state;
  String? get candidateLabel => _candidateLabel;
  String? get lastStableLabel => _lastEmittedStableLabel;
  double get lastConfidence => _lastConfidence;
  int get currentWindowSize => _currentAdaptiveWindowSize;

  /// معالجة تنبؤ إطار قادم من نموذج لغة الإشارة
  void processPrediction(SignPrediction? prediction, {bool isSignBoundary = false}) {
    final now = DateTime.now();

    // 1. فحص مهلة انقطاع اليد (Reset Timeout)
    if (_lastDetectionTime != null && now.difference(_lastDetectionTime!) > handResetTimeout) {
      _handleBlankState();
    }

    // 2. التحقق عبر بوابة الثقة (Confidence Gate) ومرشح الكلمات فقط (WordOnlyFilter)
    SignPrediction? effectivePrediction;
    if (prediction != null &&
        prediction.confidence >= retainConfidenceThreshold &&
        WordOnlyFilter.isValidWord(prediction.label)) {
      effectivePrediction = prediction;
      _lastDetectionTime = now;
      _lastConfidence = prediction.confidence;
    } else {
      // إشارة غير واضحة أو ثقة منخفضة أو حرف منفرد ➔ معاملتها كـ BLANK
      effectivePrediction = null;
    }

    // 3. إضافة الإطار إلى النافذة الزمنية المتكيفة
    _windowQueue.addLast(effectivePrediction);
    while (_windowQueue.length > _currentAdaptiveWindowSize) {
      _windowQueue.removeFirst();
    }

    // إذا كان الإطار فارغاً، تسجيل حالة BLANK
    if (effectivePrediction == null) {
      _handleBlankState();
      return;
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

    // العثور على المرشح صاحب أعلى الأصوات
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

    final double consensusRatio = maxVotes / _windowQueue.length;

    // 5. التحقق من الإنهاء المبكر (Early Exit)
    // إذا كانت الكلمة واضحة جداً وبثقة عالية وثبات ممتاز في عدد قليل من الإطارات
    final bool isEarlyExitEligible = _windowQueue.length >= minWindowSize &&
        maxVotes >= 4 &&
        avgConfidence >= earlyExitConfidence &&
        consensusRatio >= 0.70;

    // إذا كانت هناك رغبة في التوسع (حركة معقدة أو نتائج متقاربة)
    if (!isEarlyExitEligible && !isSignBoundary) {
      if (_currentAdaptiveWindowSize < maxWindowSize) {
        _currentAdaptiveWindowSize++;
      }
    } else if (isEarlyExitEligible) {
      // إعادة تقليص النافذة عند الإشارات السهلة
      _currentAdaptiveWindowSize = minWindowSize;
    }

    // 6. التحكم بالتردد (Hysteresis):
    // اعتماد كلمة جديدة يتطلب عتبة مرتفعة (adoptConfidenceThreshold)
    // بينما الاحتفاظ بالكلمة الحالية يتطلب فقط (retainConfidenceThreshold)
    final bool isSameAsCurrentCandidate = bestLabel == _candidateLabel;
    final double requiredThreshold = isSameAsCurrentCandidate
        ? retainConfidenceThreshold
        : adoptConfidenceThreshold;

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

    // 7. التحقق من الوصول لحالة الاستقرار (Stable State)
    final bool hasReachedConsensus = (maxVotes >= 3 && consensusRatio >= 0.50) ||
        isEarlyExitEligible ||
        (isSignBoundary && maxVotes >= 2);

    if (hasReachedConsensus) {
      if (_state != SignStabilityState.stable) {
        _state = SignStabilityState.stable;
        _notifyState();
      }

      // 8. منع التكرار (Duplicate Suppression) وتقليص CTC
      // لا نسمح بإضافة نفس الكلمة إلا إذا مرت حالة BLANK أو تغيرت الإشارة
      if (_lastEmittedStableLabel != bestLabel || _seenBlankSinceLastEmission) {
        _lastEmittedStableLabel = bestLabel;
        _seenBlankSinceLastEmission = false;

        final stablePred = labelPredictions[bestLabel]!.copyWith(
          confidence: avgConfidence,
        );

        if (onStableSign != null) {
          onStableSign!(stablePred);
        }

        // تفريغ النافذة بعد اعتماد الكلمة للبدء في الإشارة التالية
        _windowQueue.clear();
        _currentAdaptiveWindowSize = minWindowSize;
      }
    } else {
      if (_state != SignStabilityState.candidate) {
        _state = SignStabilityState.candidate;
        _notifyState();
      }
    }
  }

  void _handleBlankState() {
    _seenBlankSinceLastEmission = true;
    _candidateLabel = null;
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

  /// مسح الذاكرة الحالية بالكامل
  void reset() {
    _windowQueue.clear();
    _currentAdaptiveWindowSize = minWindowSize;
    _candidateLabel = null;
    _lastEmittedStableLabel = null;
    _seenBlankSinceLastEmission = true;
    _state = SignStabilityState.detecting;
    _lastDetectionTime = null;
  }
}
