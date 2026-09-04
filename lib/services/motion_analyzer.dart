import 'dart:math';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/models/landmarks_model.dart';

/// ميزات الحركة وتحليل الطاقة الحركية للإشارة
class MotionFeatures {
  final double averageVelocity;
  final double wristVelocity;
  final double directionX;
  final double directionY;
  final double directionZ;
  final double motionEnergy;
  final double angularVelocity;
  final double distanceRate;
  final bool isHandStatic;
  final bool isSignBoundary; // اكتمال الحركة والوصول لذروة الاستقرار (Apex)

  const MotionFeatures({
    required this.averageVelocity,
    required this.wristVelocity,
    required this.directionX,
    required this.directionY,
    required this.directionZ,
    required this.motionEnergy,
    required this.angularVelocity,
    required this.distanceRate,
    required this.isHandStatic,
    required this.isSignBoundary,
  });

  factory MotionFeatures.staticInitial() {
    return const MotionFeatures(
      averageVelocity: 0.0,
      wristVelocity: 0.0,
      directionX: 0.0,
      directionY: 0.0,
      directionZ: 0.0,
      motionEnergy: 0.0,
      angularVelocity: 0.0,
      distanceRate: 0.0,
      isHandStatic: true,
      isSignBoundary: false,
    );
  }
}

/// محلل حركة اليد وبوابة الحركة ورصد حدود الإشارات (Motion Analyzer & Motion Gate)
///
/// يحقق المتطلبات:
/// 1. Motion Gate: فحص ثبات اليد وتخطي الاستنتاج الزائد لتوفير CPU والبطارية.
/// 4. Motion Features: سرعة واتجاه ومقدار تغير النقاط والزوايا والمسافات.
/// 8. Sign Boundary Detection: استخدام الطاقة الحركية لرصد بداية ونهاية الإشارة.
class MotionAnalyzer {
  final double motionGateThreshold;
  final double energyStartThreshold;
  final double energyRestThreshold;

  HandLandmarks? _previousLandmarks;
  DateTime? _previousTimestamp;

  // سجل الطاقة الحركية لآخر إطارات لرصد الذروة والاستقرار (Apex Detection)
  final List<double> _recentEnergyHistory = [];
  bool _isInGestureMotion = false;
  int _consecutiveStaticFrames = 0;

  MotionAnalyzer({
    this.motionGateThreshold = AppConstants.motionGateThreshold,
    this.energyStartThreshold = AppConstants.motionEnergyStartThreshold,
    this.energyRestThreshold = AppConstants.motionEnergyRestThreshold,
  });

  /// فحص وتحليل الإطار الجديد واستخراج خصائص الحركة
  MotionFeatures analyze(HandLandmarks current) {
    if (!current.isValid || current.landmarks.length < 21) {
      reset();
      return MotionFeatures.staticInitial();
    }

    final now = DateTime.now();

    if (_previousLandmarks == null || _previousTimestamp == null) {
      _previousLandmarks = current;
      _previousTimestamp = now;
      return MotionFeatures.staticInitial();
    }

    final elapsedMs = now.difference(_previousTimestamp!).inMilliseconds;
    final dtSeconds = (elapsedMs > 0 ? elapsedMs : 75) / 1000.0;

    final currPts = current.landmarks;
    final prevPts = _previousLandmarks!.landmarks;

    // مقياس حجم الكف لتطبيع الإزاحات (المسافة من المعصم إلى قاعدة الوسطى)
    final palmScale = _dist(currPts[0], currPts[9]).clamp(0.01, 10.0);

    // 1. حساب إزاحة المعصم والسرعة
    final wristDx = currPts[0].x - prevPts[0].x;
    final wristDy = currPts[0].y - prevPts[0].y;
    final wristDz = currPts[0].z - prevPts[0].z;
    final rawWristDisplacement = sqrt(wristDx * wristDx + wristDy * wristDy + wristDz * wristDz);
    final normWristDisplacement = rawWristDisplacement / palmScale;
    final wristVel = normWristDisplacement / dtSeconds;

    // 2. حساب متوسط إزاحة كافة النقاط الـ 21 والسرعة
    double totalDisplacement = 0.0;
    double sumDirX = 0.0;
    double sumDirY = 0.0;
    double sumDirZ = 0.0;
    double sumSqDisplacement = 0.0;

    for (int i = 0; i < 21; i++) {
      final dx = currPts[i].x - prevPts[i].x;
      final dy = currPts[i].y - prevPts[i].y;
      final dz = currPts[i].z - prevPts[i].z;
      final dist = sqrt(dx * dx + dy * dy + dz * dz);
      final normDist = dist / palmScale;

      totalDisplacement += normDist;
      sumSqDisplacement += normDist * normDist;
      sumDirX += dx;
      sumDirY += dy;
      sumDirZ += dz;
    }

    final avgDisplacement = totalDisplacement / 21.0;
    final avgVelocity = avgDisplacement / dtSeconds;

    // اتجاه الحركة الموحد
    final dirMag = sqrt(sumDirX * sumDirX + sumDirY * sumDirY + sumDirZ * sumDirZ);
    final normDirX = dirMag > 0.0001 ? sumDirX / dirMag : 0.0;
    final normDirY = dirMag > 0.0001 ? sumDirY / dirMag : 0.0;
    final normDirZ = dirMag > 0.0001 ? sumDirZ / dirMag : 0.0;

    // 3. الطاقة الحركية (Kinetic / Motion Energy)
    final motionEnergy = (sumSqDisplacement / 21.0) / (dtSeconds * dtSeconds);

    // 4. معدل تغير الزوايا (Angular Velocity)
    final currThumbAngle = _calcAngle(currPts[1], currPts[2], currPts[3]);
    final prevThumbAngle = _calcAngle(prevPts[1], prevPts[2], prevPts[3]);
    final currIndexAngle = _calcAngle(currPts[5], currPts[6], currPts[7]);
    final prevIndexAngle = _calcAngle(prevPts[5], prevPts[6], prevPts[7]);
    final angularVel = ((currThumbAngle - prevThumbAngle).abs() + (currIndexAngle - prevIndexAngle).abs()) / (2.0 * dtSeconds);

    // 5. معدل تمدد/انقباض أطراف الأصابع (Distance Rate)
    final currSpread = _dist(currPts[4], currPts[20]) / palmScale;
    final prevSpread = _dist(prevPts[4], prevPts[20]) / palmScale;
    final distRate = ((currSpread - prevSpread) / dtSeconds).abs();

    // ── Motion Gate: هل اليد ثابتة؟ ──
    final bool isStatic = avgDisplacement < motionGateThreshold && normWristDisplacement < motionGateThreshold;
    if (isStatic) {
      _consecutiveStaticFrames++;
    } else {
      _consecutiveStaticFrames = 0;
    }

    // ── Sign Boundary Detection (رصد حدود الإشارة) ──
    _recentEnergyHistory.add(motionEnergy);
    if (_recentEnergyHistory.length > 8) {
      _recentEnergyHistory.removeAt(0);
    }

    bool isBoundary = false;

    // إذا ارتفعت الطاقة فوق عتبة البداية ➔ دخل المستخدم في حركة إشارة
    if (avgDisplacement > energyStartThreshold) {
      _isInGestureMotion = true;
    }

    // إذا كانت اليد في حركة ثم تباطأت واستقرت في موضع الإشارة (Apex) ➔ اكتمال حد الإشارة
    if (_isInGestureMotion && isStatic && _consecutiveStaticFrames >= 2) {
      isBoundary = true;
      _isInGestureMotion = false; // إعادة الضبط للإشارة القادمة
    }

    // تحديث الحالة للإطار القادم
    _previousLandmarks = current;
    _previousTimestamp = now;

    return MotionFeatures(
      averageVelocity: avgVelocity,
      wristVelocity: wristVel,
      directionX: normDirX,
      directionY: normDirY,
      directionZ: normDirZ,
      motionEnergy: motionEnergy,
      angularVelocity: angularVel,
      distanceRate: distRate,
      isHandStatic: isStatic,
      isSignBoundary: isBoundary,
    );
  }

  /// مسح الذاكرة الحركية (عند اختفاء اليد)
  void reset() {
    _previousLandmarks = null;
    _previousTimestamp = null;
    _recentEnergyHistory.clear();
    _isInGestureMotion = false;
    _consecutiveStaticFrames = 0;
  }

  static double _dist(HandLandmark a, HandLandmark b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return sqrt(dx * dx + dy * dy + dz * dz);
  }

  static double _calcAngle(HandLandmark a, HandLandmark b, HandLandmark c) {
    final baX = a.x - b.x;
    final baY = a.y - b.y;
    final baZ = a.z - b.z;
    final bcX = c.x - b.x;
    final bcY = c.y - b.y;
    final bcZ = c.z - b.z;
    final dot = baX * bcX + baY * bcY + baZ * bcZ;
    final magBa = sqrt(baX * baX + baY * baY + baZ * baZ);
    final magBc = sqrt(bcX * bcX + bcY * bcY + bcZ * bcZ);
    if (magBa * magBc == 0) return 0.0;
    return acos((dot / (magBa * magBc)).clamp(-1.0, 1.0));
  }
}
