import 'package:flutter/material.dart';
import 'package:ishara/models/body_parts_detection_state.dart';

/// VisionLandmarksOverlayPainter
/// رسام المعالم الحقيقية اللحظية فوق الكاميرا
/// يرسم الهيكل العظمي لـ 21 نقطة لكل يد مع أرقام النقاط من 0 إلى 20،
/// ونقاط الشفاه الـ 19، وشبكة الوجه، ومؤشرات الجسم والرأس،
/// ومعلومات التشخيص الحية (Telemetry & Freeze Monitor).
class VisionLandmarksOverlayPainter extends CustomPainter {
  final VisionLandmarksState state;
  final bool isFrontCamera;
  final bool showNumbers;
  final bool showHands;
  final bool showFaceAndLips;
  final bool showPose;
  final bool showTelemetry;

  VisionLandmarksOverlayPainter({
    required this.state,
    this.isFrontCamera = true,
    this.showNumbers = true,
    this.showHands = true,
    this.showFaceAndLips = true,
    this.showPose = true,
    this.showTelemetry = true,
  });

  // روابط الهيكل العظمي لليد الـ 21 نقطة القياسية في MediaPipe
  static const List<List<int>> handConnections = [
    // Palm / راحة اليد
    [0, 1], [0, 5], [5, 9], [9, 13], [13, 17], [0, 17],
    // Thumb / الإبهام
    [1, 2], [2, 3], [3, 4],
    // Index / السبابة
    [5, 6], [6, 7], [7, 8],
    // Middle / الوسطى
    [9, 10], [10, 11], [11, 12],
    // Ring / البنصر
    [13, 14], [14, 15], [15, 16],
    // Pinky / الخنصر
    [17, 18], [18, 19], [19, 20],
  ];

  // روابط الجزء العلوي للجسم (MediaPipe Pose)
  static const List<List<int>> poseConnections = [
    [11, 12], // الكتف الأيسر - الأيمن
    [11, 13], // الكتف الأيسر - الكوع الأيسر
    [13, 15], // الكوع الأيسر - المعصم الأيسر
    [12, 14], // الكتف الأيمن - الكوع الأيمن
    [14, 16], // الكوع الأيمن - المعصم الأيمن
    [11, 23], // الكتف الأيسر - الورك الأيسر
    [12, 24], // الكتف الأيمن - الورك الأيمن
    [23, 24], // الورك الأيسر - الأيمن
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. رسم وضعية الجسم والرأس (Pose)
    if (showPose && state.posePoints != null && state.posePoints!.isNotEmpty) {
      _drawPose(canvas, size, state.posePoints!);
    }

    // 2. رسم شبكة الوجه والشفاه الحقيقية
    if (showFaceAndLips) {
      if (state.facePoints != null && state.facePoints!.isNotEmpty) {
        _drawFaceMesh(canvas, size, state.facePoints!);
      }
      if (state.lipPoints != null && state.lipPoints!.isNotEmpty) {
        _drawLips(canvas, size, state.lipPoints!);
      }
    }

    // 3. رسم الأيدي الحقيقية (الهيكل العظمي والـ 21 نقطة والأرقام)
    if (showHands) {
      if (state.rightHandPoints != null && state.rightHandPoints!.length == 21) {
        _drawHand(
          canvas,
          size,
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
          state.leftHandPoints!,
          label: 'Left Hand',
          accentColor: const Color(0xFFFF9100), // Orange لليد اليسرى
          jointColor: Colors.white,
        );
      }
    }

    // 4. رسم شريط التشخيص الحي (Live Telemetry & Frozen Detector)
    if (showTelemetry) {
      _drawTelemetryHUD(canvas, size);
    }
  }

  /// تحويل إحداثيات النقطة الطبيعية [0..1] إلى إحداثيات الشاشة مع مراعاة Mirroring
  Offset _toScreen(double nx, double ny, Size size) {
    final double x = isFrontCamera ? (1.0 - nx) * size.width : nx * size.width;
    final double y = ny * size.height;
    return Offset(x, y);
  }

  /// رسم يد كاملة (الهيكل العظمي، المفاصل، وأرقام النقاط 0..20)
  void _drawHand(
    Canvas canvas,
    Size size,
    List<HandLandmarkPoint> points, {
    required String label,
    required Color accentColor,
    required Color jointColor,
  }) {
    final Map<int, Offset> screenPoints = {};
    for (final pt in points) {
      screenPoints[pt.index] = _toScreen(pt.x, pt.y, size);
    }

    // رسم خطوط الهيكل العظمي (Skeleton Lines)
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

    // رسم المفاصل (Joint Dots)
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

      // رسم رقم النقطة (0..20) عند تفعيل خيار Debug
      if (showNumbers) {
        _drawIndexLabel(canvas, i.toString(), pos, accentColor);
      }
    }

    // رسم تسمية اليد عند المعصم (Wrist - Point 0)
    final wrist = screenPoints[0];
    if (wrist != null) {
      _drawHandLabel(canvas, label, wrist, accentColor);
    }
  }

  /// رسم رقم النقطة بجانب المفصل
  void _drawIndexLabel(Canvas canvas, String text, Offset pos, Color accentColor) {
    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 9.0,
      fontWeight: FontWeight.bold,
      fontFamily: 'monospace',
    );

    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
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

  /// رسم تسمية اليد (Right Hand / Left Hand)
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
  void _drawLips(Canvas canvas, Size size, List<NormalizedPoint> lipPoints) {
    final lipPaint = Paint()
      ..color = const Color(0xFFFF1744) // Vibrant Crimson/Magenta
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = const Color(0xFFFF5252).withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    for (final pt in lipPoints) {
      final pos = _toScreen(pt.x, pt.y, size);
      canvas.drawCircle(pos, 4.0, glowPaint);
      canvas.drawCircle(pos, 2.5, lipPaint);
    }
  }

  /// رسم عينات شبكة الوجه (Face Mesh)
  void _drawFaceMesh(Canvas canvas, Size size, List<NormalizedPoint> facePoints) {
    final meshPaint = Paint()
      ..color = const Color(0xFF64FFDA).withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;

    for (final pt in facePoints) {
      final pos = _toScreen(pt.x, pt.y, size);
      canvas.drawCircle(pos, 1.5, meshPaint);
    }
  }

  /// رسم وضعية الجسم والرأس
  void _drawPose(Canvas canvas, Size size, List<PoseLandmarkPoint> posePoints) {
    final Map<int, Offset> screenMap = {};
    for (final pt in posePoints) {
      screenMap[pt.index] = _toScreen(pt.x, pt.y, size);
    }

    final linePaint = Paint()
      ..color = const Color(0xFF7C4DFF).withValues(alpha: 0.75) // Deep Purple
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

  /// رسم شريط معلومات الـ Live Telemetry وتنبيه التجمد
  void _drawTelemetryHUD(Canvas canvas, Size size) {
    // 1. تنبيه تجمد النقاط إذا تم اكتشافه
    if (state.isPossiblyFrozen) {
      final alertRect = Rect.fromLTWH(12, 12, size.width - 24, 28);
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
          (size.width - alertPainter.width) / 2,
          12 + (28 - alertPainter.height) / 2,
        ),
      );
    }

    // 2. بطاقة معلومات الـ Frame و FPS و Motion Delta بالأسفل
    final double hudY = size.height - 40;
    final hudRect = Rect.fromLTWH(10, hudY, size.width - 20, 30);
    final hudBg = Paint()..color = Colors.black.withValues(alpha: 0.65);
    canvas.drawRRect(RRect.fromRectAndRadius(hudRect, const Radius.circular(10)), hudBg);

    final hudText = 'Frame: #${state.frameId} | Res: #${state.detectorResultId} | Age: ${state.landmarkAgeMs}ms | Δ: ${state.motionDelta.toStringAsFixed(3)} | ${state.fps.toStringAsFixed(1)} FPS';

    final hudPainter = TextPainter(
      text: TextSpan(
        text: hudText,
        style: const TextStyle(
          color: Color(0xFFE0E0E0),
          fontSize: 10.5,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    hudPainter.paint(
      canvas,
      Offset(
        (size.width - hudPainter.width) / 2,
        hudY + (30 - hudPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant VisionLandmarksOverlayPainter oldDelegate) {
    return oldDelegate.state.frameId != state.frameId ||
        oldDelegate.state.detectorResultId != state.detectorResultId ||
        oldDelegate.state.timestamp != state.timestamp ||
        oldDelegate.state.isPossiblyFrozen != state.isPossiblyFrozen ||
        oldDelegate.showNumbers != showNumbers ||
        oldDelegate.showHands != showHands ||
        oldDelegate.showFaceAndLips != showFaceAndLips ||
        oldDelegate.showPose != showPose ||
        oldDelegate.showTelemetry != showTelemetry ||
        oldDelegate.isFrontCamera != isFrontCamera;
  }
}
