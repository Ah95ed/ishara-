import 'package:flutter/material.dart';
import 'package:ishara/models/body_parts_detection_state.dart';
import 'package:ishara/services/camera_landmark_mapper.dart';

/// VisionLandmarksOverlayPainter
/// رسام المعالم الحقيقية اللحظية فوق الكاميرا مع المحول الهندسي الموحد
/// يدعم:
/// 1. وضع المعايرة النقطية (Nose Calibration Mode) لفحص دقة المحاذاة بنقطة واحدة
/// 2. رسم الهيكل العظمي للأيدي (21 نقطة) وأرقامها
/// 3. رسم نقاط الشفاه (19 نقطة) وشبكة الوجه ووضعية الجسم
/// 4. شريط التشخيص الحي وCrosshairs
class VisionLandmarksOverlayPainter extends CustomPainter {
  final VisionLandmarksState state;
  final bool isFrontCamera;
  final bool showNumbers;
  final bool showHands;
  final bool showFaceAndLips;
  final bool showPose;
  final bool showTelemetry;
  final bool calibrationMode; // عند التفعيل: يركز على نقطة الأنف ومعالم الوجه الأساسية لفحص الدقة

  VisionLandmarksOverlayPainter({
    required this.state,
    this.isFrontCamera = true,
    this.showNumbers = true,
    this.showHands = true,
    this.showFaceAndLips = true,
    this.showPose = true,
    this.showTelemetry = true,
    this.calibrationMode = false,
  });

  // روابط الهيكل العظمي لليد الـ 21 نقطة القياسية في MediaPipe
  static const List<List<int>> handConnections = [
    [0, 1], [0, 5], [5, 9], [9, 13], [13, 17], [0, 17],
    [1, 2], [2, 3], [3, 4],
    [5, 6], [6, 7], [7, 8],
    [9, 10], [10, 11], [11, 12],
    [13, 14], [14, 15], [15, 16],
    [17, 18], [18, 19], [19, 20],
  ];

  // روابط الجزء العلوي للجسم (MediaPipe Pose)
  static const List<List<int>> poseConnections = [
    [11, 12], [11, 13], [13, 15], [12, 14],
    [14, 16], [11, 23], [12, 24], [23, 24],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final Size srcSize = state.sourceImageSize.width > 0
        ? state.sourceImageSize
        : const Size(480, 640);

    // ── وضع المعايرة النقطية وفحص الأنف (Nose Calibration Mode) ──
    if (calibrationMode) {
      _drawCalibrationCrosshair(canvas, size, srcSize);
      _drawNoseAndKeyAnchors(canvas, size, srcSize);
      if (showTelemetry) _drawTelemetryHUD(canvas, size, srcSize);
      return;
    }

    // ── وضع العرض الكامل (Full Mesh & Skeletons) ──
    // 1. رسم وضعية الجسم والرأس (Pose)
    if (showPose && state.posePoints != null && state.posePoints!.isNotEmpty) {
      _drawPose(canvas, size, srcSize, state.posePoints!);
    }

    // 2. رسم شبكة الوجه والشفاه الحقيقية عبر نفس الـ Mapper الموحد
    if (showFaceAndLips) {
      if (state.facePoints != null && state.facePoints!.isNotEmpty) {
        _drawFaceMesh(canvas, size, srcSize, state.facePoints!);
      }
      if (state.lipPoints != null && state.lipPoints!.isNotEmpty) {
        _drawLips(canvas, size, srcSize, state.lipPoints!);
      }
    }

    // 3. رسم الأيدي الحقيقية (الهيكل العظمي والـ 21 نقطة والأرقام)
    if (showHands) {
      if (state.rightHandPoints != null && state.rightHandPoints!.length == 21) {
        _drawHand(
          canvas,
          size,
          srcSize,
          state.rightHandPoints!,
          label: 'Right Hand',
          accentColor: const Color(0xFF00E5FF), // Cyan لليد اليمنى
          jointColor: Colors.white,
        );
      }

      if (state.leftHandPoints != null && state.leftHandPoints!.length == 21) {
        _drawHand(
          canvas,
          size,
          srcSize,
          state.leftHandPoints!,
          label: 'Left Hand',
          accentColor: const Color(0xFFFF9100), // Orange لليد اليسرى
          jointColor: Colors.white,
        );
      }
    }

    // 4. رسم شريط التشخيص الحي
    if (showTelemetry) {
      _drawTelemetryHUD(canvas, size, srcSize);
    }
  }

  /// تحويل نقطة باستخدام المحول الهندسي الموحد CameraLandmarkMapper
  Offset _toScreen(double nx, double ny, Size previewSize, Size sourceSize) {
    return CameraLandmarkMapper.map(
      normalizedX: nx,
      normalizedY: ny,
      sourceImageSize: sourceSize,
      previewSize: previewSize,
      isFrontCamera: isFrontCamera,
      isPreviewMirrored: true, // CameraPreview الأمامية على Android معكوسة دائماً
      fitMode: BoxFit.contain,
    );
  }

  /// رسم خطوط التقاطع وحدود الصورة لأغراض التشخيص (Debug Crosshair)
  void _drawCalibrationCrosshair(Canvas canvas, Size previewSize, Size sourceSize) {
    final center = Offset(previewSize.width / 2, previewSize.height / 2);
    final crossPaint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.35)
      ..strokeWidth = 1.0;

    // خط أفقي ورأسي في منتصف المعاينة
    canvas.drawLine(Offset(0, center.dy), Offset(previewSize.width, center.dy), crossPaint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, previewSize.height), crossPaint);

    // رسم حدود الصورة المحجوبة والمحاذاة داخل الشاشة
    final scaledRect = CameraLandmarkMapper.getScaledSourceRect(
      sourceImageSize: sourceSize,
      previewSize: previewSize,
      fitMode: BoxFit.contain,
    );

    final borderPaint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRect(scaledRect, borderPaint);
  }

  /// رسم نقطة الأنف رقم 1 ونقاط الوجه الأساسية للتأكد من المحاذاة الدقيقة
  void _drawNoseAndKeyAnchors(Canvas canvas, Size previewSize, Size sourceSize) {
    // 1. نقطة الأنف (Nose Tip #1)
    if (state.noseTipPoint != null) {
      final nosePos = _toScreen(state.noseTipPoint!.x, state.noseTipPoint!.y, previewSize, sourceSize);

      // دائرة خارجية متوهجة
      final glowPaint = Paint()
        ..color = Colors.yellowAccent.withValues(alpha: 0.4)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(nosePos, 14, glowPaint);

      // حلقة استهداف
      final ringPaint = Paint()
        ..color = Colors.yellowAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(nosePos, 8, ringPaint);

      // مركز الهدف
      final dotPaint = Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(nosePos, 3.5, dotPaint);

      // علامة نصية
      _drawTextBadge(canvas, '🎯 NOSE (#1)', Offset(nosePos.dx + 12, nosePos.dy - 12), Colors.yellowAccent);
    }

    // 2. العين اليسرى (#33)
    if (state.leftEyePoint != null) {
      final pos = _toScreen(state.leftEyePoint!.x, state.leftEyePoint!.y, previewSize, sourceSize);
      _drawAnchorPoint(canvas, pos, 'L-EYE (#33)', Colors.cyanAccent);
    }

    // 3. العين اليمنى (#263)
    if (state.rightEyePoint != null) {
      final pos = _toScreen(state.rightEyePoint!.x, state.rightEyePoint!.y, previewSize, sourceSize);
      _drawAnchorPoint(canvas, pos, 'R-EYE (#263)', Colors.cyanAccent);
    }

    // 4. الشفة العلوية (#0)
    if (state.upperLipCenterPoint != null) {
      final pos = _toScreen(state.upperLipCenterPoint!.x, state.upperLipCenterPoint!.y, previewSize, sourceSize);
      _drawAnchorPoint(canvas, pos, 'UPPER-LIP (#0)', Colors.pinkAccent);
    }

    // 5. الشفة السفلية (#17)
    if (state.lowerLipCenterPoint != null) {
      final pos = _toScreen(state.lowerLipCenterPoint!.x, state.lowerLipCenterPoint!.y, previewSize, sourceSize);
      _drawAnchorPoint(canvas, pos, 'LOWER-LIP (#17)', Colors.pinkAccent);
    }

    // 6. الذقن (#152)
    if (state.chinPoint != null) {
      final pos = _toScreen(state.chinPoint!.x, state.chinPoint!.y, previewSize, sourceSize);
      _drawAnchorPoint(canvas, pos, 'CHIN (#152)', Colors.lightGreenAccent);
    }
  }

  void _drawAnchorPoint(Canvas canvas, Offset pos, String label, Color color) {
    canvas.drawCircle(pos, 6, Paint()..color = color.withValues(alpha: 0.35)..style = PaintingStyle.fill);
    canvas.drawCircle(pos, 3.5, Paint()..color = color..style = PaintingStyle.fill);
    _drawTextBadge(canvas, label, Offset(pos.dx + 8, pos.dy - 8), color);
  }

  void _drawTextBadge(Canvas canvas, String text, Offset pos, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black.withValues(alpha: 0.75),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(canvas, pos);
  }

  /// رسم يد كاملة (الهيكل العظمي، المفاصل، وأرقام النقاط 0..20)
  void _drawHand(
    Canvas canvas,
    Size previewSize,
    Size sourceSize,
    List<HandLandmarkPoint> points, {
    required String label,
    required Color accentColor,
    required Color jointColor,
  }) {
    final Map<int, Offset> screenPoints = {};
    for (final pt in points) {
      screenPoints[pt.index] = _toScreen(pt.x, pt.y, previewSize, sourceSize);
    }

    final bonePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.85)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final glowPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.35)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final conn in handConnections) {
      final p1 = screenPoints[conn[0]];
      final p2 = screenPoints[conn[1]];
      if (p1 != null && p2 != null) {
        canvas.drawLine(p1, p2, glowPaint);
        canvas.drawLine(p1, p2, bonePaint);
      }
    }

    final jointBgPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    final jointFgPaint = Paint()
      ..color = jointColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 21; i++) {
      final pos = screenPoints[i];
      if (pos == null) continue;

      final double radius = (i == 0 || i == 4 || i == 8 || i == 12 || i == 16 || i == 20)
          ? 5.0
          : 3.5;

      canvas.drawCircle(pos, radius + 1.5, jointBgPaint);
      canvas.drawCircle(pos, radius, jointFgPaint);

      if (showNumbers) {
        _drawIndexLabel(canvas, i.toString(), pos, accentColor);
      }
    }

    final wrist = screenPoints[0];
    if (wrist != null) {
      _drawHandLabel(canvas, label, wrist, accentColor);
    }
  }

  void _drawIndexLabel(Canvas canvas, String text, Offset pos, Color accentColor) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.0,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelOffset = Offset(pos.dx + 5, pos.dy - 6);
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        labelOffset.dx - 2,
        labelOffset.dy - 1,
        textPainter.width + 4,
        textPainter.height + 2,
      ),
      const Radius.circular(4),
    );

    final bgPaint = Paint()..color = Colors.black.withValues(alpha: 0.75);
    final borderPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.6)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(bgRect, bgPaint);
    canvas.drawRRect(bgRect, borderPaint);
    textPainter.paint(canvas, labelOffset);
  }

  void _drawHandLabel(Canvas canvas, String label, Offset wristPos, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: ' $label 21/21 ',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          backgroundColor: color.withValues(alpha: 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(canvas, Offset(wristPos.dx - (textPainter.width / 2), wristPos.dy + 12));
  }

  /// رسم نقاط الشفاه الحقيقية (19 نقطة)
  void _drawLips(Canvas canvas, Size previewSize, Size sourceSize, List<NormalizedPoint> lipPoints) {
    final lipPaint = Paint()
      ..color = const Color(0xFFFF1744)
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = const Color(0xFFFF5252).withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    for (final pt in lipPoints) {
      final pos = _toScreen(pt.x, pt.y, previewSize, sourceSize);
      canvas.drawCircle(pos, 4.0, glowPaint);
      canvas.drawCircle(pos, 2.5, lipPaint);
    }
  }

  /// رسم عينات شبكة الوجه (Face Mesh)
  void _drawFaceMesh(Canvas canvas, Size previewSize, Size sourceSize, List<NormalizedPoint> facePoints) {
    final meshPaint = Paint()
      ..color = const Color(0xFF64FFDA).withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;

    for (final pt in facePoints) {
      final pos = _toScreen(pt.x, pt.y, previewSize, sourceSize);
      canvas.drawCircle(pos, 1.5, meshPaint);
    }
  }

  /// رسم وضعية الجسم والرأس
  void _drawPose(Canvas canvas, Size previewSize, Size sourceSize, List<PoseLandmarkPoint> posePoints) {
    final Map<int, Offset> screenMap = {};
    for (final pt in posePoints) {
      screenMap[pt.index] = _toScreen(pt.x, pt.y, previewSize, sourceSize);
    }

    final linePaint = Paint()
      ..color = const Color(0xFF7C4DFF).withValues(alpha: 0.75)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (final conn in poseConnections) {
      final p1 = screenMap[conn[0]];
      final p2 = screenMap[conn[1]];
      if (p1 != null && p2 != null) {
        canvas.drawLine(p1, p2, linePaint);
      }
    }

    final ptPaint = Paint()
      ..color = const Color(0xFFB388FF)
      ..style = PaintingStyle.fill;

    for (final pt in posePoints) {
      final pos = screenMap[pt.index];
      if (pos != null) {
        canvas.drawCircle(pos, 3.5, ptPaint);
      }
    }
  }

  /// رسم شريط معلومات الـ Live Telemetry وتنبيه التجمد ومقاييس التحويل
  void _drawTelemetryHUD(Canvas canvas, Size previewSize, Size sourceSize) {
    // 1. تنبيه تجمد النقاط
    if (state.isPossiblyFrozen) {
      final alertRect = Rect.fromLTWH(12, 12, previewSize.width - 24, 28);
      final alertPaint = Paint()..color = Colors.red.withValues(alpha: 0.88);
      canvas.drawRRect(RRect.fromRectAndRadius(alertRect, const Radius.circular(8)), alertPaint);

      final alertPainter = TextPainter(
        text: const TextSpan(
          text: '⚠️ LANDMARKS POSSIBLY FROZEN (Motion Δ ≈ 0)',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      alertPainter.paint(
        canvas,
        Offset(
          (previewSize.width - alertPainter.width) / 2,
          12 + (28 - alertPainter.height) / 2,
        ),
      );
    }

    // 2. بطاقة معلومات الـ Frame و FPS ومقاييس التحويل (المتطلب 8)
    final double hudY = previewSize.height - 40;
    final hudRect = Rect.fromLTWH(8, hudY, previewSize.width - 16, 32);
    final hudBg = Paint()..color = Colors.black.withValues(alpha: 0.70);
    canvas.drawRRect(RRect.fromRectAndRadius(hudRect, const Radius.circular(10)), hudBg);

    final String modeLabel = calibrationMode ? '🎯 CALIBRATION' : 'LIVE';
    final hudText = '$modeLabel | #${state.frameId} | Src: ${sourceSize.width.toInt()}x${sourceSize.height.toInt()} | Dst: ${previewSize.width.toInt()}x${previewSize.height.toInt()} | Δ: ${state.motionDelta.toStringAsFixed(3)} | ${state.fps.toStringAsFixed(1)} FPS';

    final hudPainter = TextPainter(
      text: TextSpan(
        text: hudText,
        style: const TextStyle(
          color: Color(0xFFE0E0E0),
          fontSize: 9.5,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    hudPainter.paint(
      canvas,
      Offset(
        (previewSize.width - hudPainter.width) / 2,
        hudY + (32 - hudPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant VisionLandmarksOverlayPainter oldDelegate) {
    return oldDelegate.state.frameId != state.frameId ||
        oldDelegate.state.detectorResultId != state.detectorResultId ||
        oldDelegate.state.timestamp != state.timestamp ||
        oldDelegate.state.isPossiblyFrozen != state.isPossiblyFrozen ||
        oldDelegate.calibrationMode != calibrationMode ||
        oldDelegate.showNumbers != showNumbers ||
        oldDelegate.showHands != showHands ||
        oldDelegate.showFaceAndLips != showFaceAndLips ||
        oldDelegate.showPose != showPose ||
        oldDelegate.showTelemetry != showTelemetry ||
        oldDelegate.isFrontCamera != isFrontCamera;
  }
}
