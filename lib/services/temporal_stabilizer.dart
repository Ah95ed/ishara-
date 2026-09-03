import 'package:ishara/models/sign_prediction_model.dart';

enum SignStabilityState { detecting, candidate, stable }

/// مرشح الثبات الزمني ومنع التكرار (Temporal Stabilization & Voting)
/// يمنع التذبذب بين الإطارات ويحول التنبؤات اللحظية إلى إشارات مستقرة مؤكدة
class TemporalStabilizer {
  final int requiredConsecutiveMatches;
  final double minConfidenceThreshold;
  final Duration handResetTimeout;

  SignStabilityState _state = SignStabilityState.detecting;
  String? _candidateLabel;
  int _consecutiveMatchCount = 0;
  String? _lastEmittedStableLabel;
  DateTime? _lastDetectionTime;
  double _lastConfidence = 0.0;

  // رد نداء عند ثبات إشارة جديدة غير مكررة
  void Function(SignPrediction stablePrediction)? onStableSign;
  // رد نداء عند تغير حالة الاستقرار (detecting / candidate / stable)
  void Function(SignStabilityState state, String? label, double confidence)? onStateChanged;

  TemporalStabilizer({
    this.requiredConsecutiveMatches = 3,
    this.minConfidenceThreshold = 0.70,
    this.handResetTimeout = const Duration(milliseconds: 900),
  });

  SignStabilityState get state => _state;
  String? get candidateLabel => _candidateLabel;
  String? get lastStableLabel => _lastEmittedStableLabel;
  double get lastConfidence => _lastConfidence;

  /// معالجة تنبؤ خام قادم من نموذج الإشارة في كل إطار
  void processPrediction(SignPrediction? prediction) {
    final now = DateTime.now();

    // فحص انقطاع اليد (Reset Timeout)
    if (_lastDetectionTime != null && now.difference(_lastDetectionTime!) > handResetTimeout) {
      _resetCandidate();
    }

    if (prediction == null || prediction.confidence < minConfidenceThreshold || prediction.label.trim().isEmpty) {
      if (_state != SignStabilityState.detecting) {
        _state = SignStabilityState.detecting;
        _notifyState();
      }
      return;
    }

    _lastDetectionTime = now;
    _lastConfidence = prediction.confidence;
    final label = prediction.label.trim();

    // 1. التصويت والمطابقة المتتابعة (Consecutive Voting)
    if (label == _candidateLabel) {
      _consecutiveMatchCount++;
    } else {
      _candidateLabel = label;
      _consecutiveMatchCount = 1;
      _state = SignStabilityState.candidate;
      _notifyState();
    }

    // 2. التحقق من الوصول إلى حد الثبات (Stable Threshold)
    if (_consecutiveMatchCount >= requiredConsecutiveMatches) {
      if (_state != SignStabilityState.stable) {
        _state = SignStabilityState.stable;
        _notifyState();
      }

      // 3. منع التكرار المتصل (Duplicate Prevention)
      // إذا كانت نفس الكلمة السابقة مستمرة (مثل: ماء ماء ماء)، لا نكرر الإرسال
      if (_lastEmittedStableLabel != label) {
        _lastEmittedStableLabel = label;
        if (onStableSign != null) {
          onStableSign!(prediction);
        }
      }
    }
  }

  void _resetCandidate() {
    _candidateLabel = null;
    _consecutiveMatchCount = 0;
    _state = SignStabilityState.detecting;
    _notifyState();
  }

  void _notifyState() {
    if (onStateChanged != null) {
      onStateChanged!(_state, _candidateLabel, _lastConfidence);
    }
  }

  /// مسح الذاكرة الحالية (مثلاً عند اختفاء اليد أو مسح الشاشة)
  void reset() {
    _resetCandidate();
    _lastEmittedStableLabel = null;
  }
}
