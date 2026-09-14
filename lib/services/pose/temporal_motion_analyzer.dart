import 'dart:math';

/// نتائج تحليل الحركة الزمنية لإطار
class TemporalMotionResult {
  final double motionEnergy;
  final double handVelocity;
  final double handAcceleration;
  final double headVelocity;
  final double relativeHandToHeadDist;
  final double directionX;
  final double directionY;
  final bool isAboveStartThreshold;
  final bool isAboveActiveThreshold;
  final bool isBelowEndThreshold;

  const TemporalMotionResult({
    required this.motionEnergy,
    required this.handVelocity,
    required this.handAcceleration,
    required this.headVelocity,
    required this.relativeHandToHeadDist,
    required this.directionX,
    required this.directionY,
    required this.isAboveStartThreshold,
    required this.isAboveActiveThreshold,
    required this.isBelowEndThreshold,
  });

  static const TemporalMotionResult zero = TemporalMotionResult(
    motionEnergy: 0.0,
    handVelocity: 0.0,
    handAcceleration: 0.0,
    headVelocity: 0.0,
    relativeHandToHeadDist: 0.0,
    directionX: 0.0,
    directionY: 0.0,
    isAboveStartThreshold: false,
    isAboveActiveThreshold: false,
    isBelowEndThreshold: true,
  );
}

/// محلل الحركة الزمني وطاقة الحركة (TemporalMotionAnalyzer)
///
/// يحلل الإشارة كحركة زمنية مستمرة وليس Pose مفردة:
/// - يراقب المعاصم والأصابع والرأس والحركة النسبية لليد بالنسبة للوجه/الرأس.
/// - يحسب طاقة الحركة الموزونة (Motion Energy).
/// - يدير الـ Pre-roll والذاكرة الحركية القصيرة.
class TemporalMotionAnalyzer {
  double motionStartThreshold;
  double motionActiveThreshold;
  double motionEndThreshold;

  // أوزان طاقة الحركة المعتمدة
  final double handWeight;
  final double headBodyWeight;
  final double faceLipsWeight;

  // تاريخ النقاط لحساب المشتقات الحركية (Velocity & Acceleration)
  final List<List<double>> _recentHandPoints = [];
  final List<List<double>> _recentHeadPoints = [];
  final List<double> _recentVelocities = [];
  final List<double> _recentEnergies = [];

  // مخزن الـ Pre-roll لحفظ الإطارات السابقة لبدء الحركة (8-16 إطار)
  final List<List<List<double>>> _preRollBuffer = [];
  final int preRollCapacity;

  DateTime? _lastTimestamp;
  double _lastVelocity = 0.0;

  TemporalMotionAnalyzer({
    this.motionStartThreshold = 0.022,
    this.motionActiveThreshold = 0.015,
    this.motionEndThreshold = 0.009,
    this.handWeight = 0.65,
    this.headBodyWeight = 0.25,
    this.faceLipsWeight = 0.10,
    this.preRollCapacity = 12,
  });

  List<List<List<double>>> get preRollFrames =>
      List.unmodifiable(_preRollBuffer);

  /// إضافة إطار للـ Pre-roll أثناء حالة الاستعداد (READY)
  void recordPreRollFrame(List<List<double>> frame86x2) {
    _preRollBuffer.add(List.generate(
      frame86x2.length,
      (i) => List<double>.from(frame86x2[i]),
    ));
    if (_preRollBuffer.length > preRollCapacity) {
      _preRollBuffer.removeAt(0);
    }
  }

  /// تفريغ مخزن الـ Pre-roll
  void clearPreRoll() {
    _preRollBuffer.clear();
  }

  /// تحليل الحركة في الإطار الحالي
  TemporalMotionResult analyzeFrame({
    List<List<double>>? rightHand,
    List<List<double>>? leftHand,
    List<List<double>>? lips,
    List<List<double>>? body,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();
    final double dt = _lastTimestamp != null
        ? (now.difference(_lastTimestamp!).inMilliseconds / 1000.0).clamp(0.015, 0.200)
        : 0.033;
    _lastTimestamp = now;

    // 1. استخراج نقطة المعصم وطرف السبابة من اليد المتاحة
    List<double>? activeHandWrist;
    List<double>? activeHandTip;

    if (rightHand != null && rightHand.length >= 9 && !_isZero(rightHand[0])) {
      activeHandWrist = rightHand[0];
      activeHandTip = rightHand[8];
    } else if (leftHand != null && leftHand.length >= 9 && !_isZero(leftHand[0])) {
      activeHandWrist = leftHand[0];
      activeHandTip = leftHand[8];
    }

    // 2. استخراج نقطة الرأس (الأنف أو مركز الشفاه)
    List<double>? headPoint;
    if (body != null && body.isNotEmpty && !_isZero(body[0])) {
      headPoint = body[0]; // Nose
    } else if (lips != null && lips.isNotEmpty && !_isZero(lips[0])) {
      headPoint = lips[0];
    }

    // 3. حساب سرعة حركة اليد
    double handVelocity = 0.0;
    double dirX = 0.0;
    double dirY = 0.0;

    if (activeHandWrist != null) {
      if (_recentHandPoints.isNotEmpty) {
        final prev = _recentHandPoints.last;
        final dx = activeHandWrist[0] - prev[0];
        final dy = activeHandWrist[1] - prev[1];
        final disp = sqrt(dx * dx + dy * dy);
        handVelocity = disp / dt;
        if (disp > 1e-5) {
          dirX = dx / disp;
          dirY = dy / disp;
        }
      }
      _recentHandPoints.add([activeHandWrist[0], activeHandWrist[1]]);
      if (_recentHandPoints.length > 6) _recentHandPoints.removeAt(0);
    } else {
      _recentHandPoints.clear();
    }

    // 4. حساب تسارع اليد
    final double handAcceleration = (handVelocity - _lastVelocity) / dt;
    _lastVelocity = handVelocity;
    _recentVelocities.add(handVelocity);
    if (_recentVelocities.length > 5) _recentVelocities.removeAt(0);

    // 5. حساب سرعة حركة الرأس
    double headVelocity = 0.0;
    if (headPoint != null) {
      if (_recentHeadPoints.isNotEmpty) {
        final prevHead = _recentHeadPoints.last;
        final dx = headPoint[0] - prevHead[0];
        final dy = headPoint[1] - prevHead[1];
        headVelocity = sqrt(dx * dx + dy * dy) / dt;
      }
      _recentHeadPoints.add([headPoint[0], headPoint[1]]);
      if (_recentHeadPoints.length > 6) _recentHeadPoints.removeAt(0);
    } else {
      _recentHeadPoints.clear();
    }

    // 6. المسافة النسبية بين اليد والرأس
    double relativeHandToHead = 0.0;
    if (activeHandWrist != null && headPoint != null) {
      final dx = activeHandWrist[0] - headPoint[0];
      final dy = activeHandWrist[1] - headPoint[1];
      relativeHandToHead = sqrt(dx * dx + dy * dy);
    }

    // 7. حساب طاقة الحركة الإجمالية الموزونة (Weighted Motion Energy)
    // نأخذ الإزاحات المباشرة الطبيعية لتكون مستقلة عن تقلبات dt القصوى
    double handDisp = 0.0;
    if (_recentHandPoints.length >= 2) {
      final pCurr = _recentHandPoints.last;
      final pPrev = _recentHandPoints[_recentHandPoints.length - 2];
      handDisp = sqrt(pow(pCurr[0] - pPrev[0], 2) + pow(pCurr[1] - pPrev[1], 2));
      // إضافة حركة طرف الإصبع لتمييز حركة الأصابع حتى لو كان المعصم شبه ثابت
      if (activeHandTip != null && _recentHandPoints.length >= 2) {
        // حركة طرف الإصبع تسهم بنسبة إضافية
        handDisp = handDisp * 0.7 + 0.3 * (handVelocity * dt);
      }
    }

    double headDisp = 0.0;
    if (_recentHeadPoints.length >= 2) {
      final pCurr = _recentHeadPoints.last;
      final pPrev = _recentHeadPoints[_recentHeadPoints.length - 2];
      headDisp = sqrt(pow(pCurr[0] - pPrev[0], 2) + pow(pCurr[1] - pPrev[1], 2));
    }

    final double motionEnergy = (handDisp * handWeight) +
        (headDisp * headBodyWeight) +
        ((handDisp * 0.2) * faceLipsWeight);

    _recentEnergies.add(motionEnergy);
    if (_recentEnergies.length > 5) _recentEnergies.removeAt(0);

    // حساب متوسط الطاقة عبر آخر 3 إطارات لتجنب الضوضاء اللحظية
    final double smoothedEnergy =
        _recentEnergies.reduce((a, b) => a + b) / _recentEnergies.length;

    return TemporalMotionResult(
      motionEnergy: smoothedEnergy,
      handVelocity: handVelocity,
      handAcceleration: handAcceleration,
      headVelocity: headVelocity,
      relativeHandToHeadDist: relativeHandToHead,
      directionX: dirX,
      directionY: dirY,
      isAboveStartThreshold: smoothedEnergy >= motionStartThreshold,
      isAboveActiveThreshold: smoothedEnergy >= motionActiveThreshold,
      isBelowEndThreshold: smoothedEnergy < motionEndThreshold,
    );
  }

  void reset() {
    _recentHandPoints.clear();
    _recentHeadPoints.clear();
    _recentVelocities.clear();
    _recentEnergies.clear();
    _preRollBuffer.clear();
    _lastTimestamp = null;
    _lastVelocity = 0.0;
  }

  static bool _isZero(List<double> pt) {
    return pt.length >= 2 && pt[0].abs() < 1e-6 && pt[1].abs() < 1e-6;
  }
}
