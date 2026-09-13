import 'dart:math';

enum SignActivityState {
  noSign,
  transition,
  signActive,
}

/// كاشف وبوابة نشاط الإشارة (SignActivityDetector)
/// يتحقق بدقة من وجود يد حقيقية وطاقة حركة زمنية (Temporal Motion Energy)
/// قبل السماح بتشغيل نموذج TFLite، لمنع الـ False Positives تماماً عند السكون أو الحركات العشوائية.
class SignActivityDetector {
  final double minMotionEnergy;
  final double minHandConfidence;
  final int minValidKeypoints;

  // تاريخ مواقع المعاصم والأصابع لحساب طاقة الحركة
  final List<List<double>> _recentWristPositions = [];
  final List<List<double>> _recentFingertipPositions = [];
  static const int _historyWindow = 5;

  SignActivityState _currentState = SignActivityState.noSign;
  double _lastMotionEnergy = 0.0;
  double _lastVelocity = 0.0;
  DateTime? _lastFrameTime;

  SignActivityDetector({
    this.minMotionEnergy = 0.015,
    this.minHandConfidence = 0.40,
    this.minValidKeypoints = 15,
  });

  SignActivityState get currentState => _currentState;
  double get lastMotionEnergy => _lastMotionEnergy;
  double get lastVelocity => _lastVelocity;
  bool get isSignActive => _currentState == SignActivityState.signActive;

  /// تقييم الإطار الحالي وتحديد ما إذا كان نشاط إشارة حقيقي يستدعي تشغيل الموديل
  SignActivityState evaluateFrame({
    required List<List<double>>? rightHand,
    required List<List<double>>? leftHand,
    double rightHandConfidence = 0.0,
    double leftHandConfidence = 0.0,
  }) {
    final now = DateTime.now();
    final double dt = _lastFrameTime != null
        ? (now.difference(_lastFrameTime!).inMilliseconds / 1000.0).clamp(0.016, 0.200)
        : 0.033;
    _lastFrameTime = now;

    // 1. التحقق من وجود يد واحدة على الأقل صالحة
    final bool hasRightHand = rightHand != null &&
        rightHand.length == 21 &&
        rightHandConfidence >= minHandConfidence &&
        !_isAllZeros(rightHand);

    final bool hasLeftHand = leftHand != null &&
        leftHand.length == 21 &&
        leftHandConfidence >= minHandConfidence &&
        !_isAllZeros(leftHand);

    if (!hasRightHand && !hasLeftHand) {
      _recentWristPositions.clear();
      _recentFingertipPositions.clear();
      _lastMotionEnergy = 0.0;
      _lastVelocity = 0.0;
      _currentState = SignActivityState.noSign;
      return SignActivityState.noSign;
    }

    // 2. حساب موقع المعصم وطرف السبابة النشطة
    final activeHand = hasRightHand ? rightHand : leftHand!;
    final wristX = activeHand[0][0];
    final wristY = activeHand[0][1];
    final tipX = activeHand[8][0]; // طرف السبابة (Index tip)
    final tipY = activeHand[8][1];

    _recentWristPositions.add([wristX, wristY]);
    _recentFingertipPositions.add([tipX, tipY]);

    if (_recentWristPositions.length > _historyWindow) {
      _recentWristPositions.removeAt(0);
      _recentFingertipPositions.removeAt(0);
    }

    // 3. حساب طاقة الحركة اللحظية عبر التاريخ القريب
    if (_recentWristPositions.length >= 2) {
      double totalDisp = 0.0;
      for (int i = 1; i < _recentWristPositions.length; i++) {
        final dw = _dist(
          _recentWristPositions[i][0],
          _recentWristPositions[i][1],
          _recentWristPositions[i - 1][0],
          _recentWristPositions[i - 1][1],
        );
        final dtp = _dist(
          _recentFingertipPositions[i][0],
          _recentFingertipPositions[i][1],
          _recentFingertipPositions[i - 1][0],
          _recentFingertipPositions[i - 1][1],
        );
        totalDisp += (dw * 0.4 + dtp * 0.6);
      }
      _lastMotionEnergy = totalDisp / (_recentWristPositions.length - 1);
      _lastVelocity = _lastMotionEnergy / dt;
    } else {
      _lastMotionEnergy = 0.0;
      _lastVelocity = 0.0;
    }

    // 4. تصنيف الحالة
    if (_lastMotionEnergy >= minMotionEnergy) {
      _currentState = SignActivityState.signActive;
    } else if (_lastMotionEnergy >= minMotionEnergy * 0.4) {
      _currentState = SignActivityState.transition;
    } else {
      _currentState = SignActivityState.noSign;
    }

    return _currentState;
  }

  static double _dist(double x1, double y1, double x2, double y2) {
    final dx = x1 - x2;
    final dy = y1 - y2;
    return sqrt(dx * dx + dy * dy);
  }

  static bool _isAllZeros(List<List<double>> pts) {
    for (final p in pts) {
      if (p[0].abs() > 1e-5 || p[1].abs() > 1e-5) return false;
    }
    return true;
  }

  void reset() {
    _recentWristPositions.clear();
    _recentFingertipPositions.clear();
    _lastMotionEnergy = 0.0;
    _lastVelocity = 0.0;
    _currentState = SignActivityState.noSign;
    _lastFrameTime = null;
  }
}
