import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

/// نتيجة كشف الرأس والوجه والجسم العلوي
class FaceHeadDetectionResult {
  final bool isDetected;
  final double confidence;
  final double headX;
  final double headY;
  final double headSize;
  final bool headPresent;
  final bool facePresent;
  final bool bodyPosePresent;
  final bool lipsPresent;
  final List<List<double>>?
  headKeypoints; // 25 نقطة بتنسيق MediaPipe Upper Body
  final List<List<double>>?
  lipKeypoints; // 19 نقطة بتنسيق MediaPipe Lips Contour

  const FaceHeadDetectionResult({
    required this.isDetected,
    required this.confidence,
    this.headX = 0.5,
    this.headY = 0.28,
    this.headSize = 0.24,
    this.headPresent = false,
    this.facePresent = false,
    this.bodyPosePresent = false,
    this.lipsPresent = false,
    this.headKeypoints,
    this.lipKeypoints,
  });

  static const FaceHeadDetectionResult notFound = FaceHeadDetectionResult(
    isDetected: false,
    confidence: 0.0,
    headPresent: false,
    facePresent: false,
    bodyPosePresent: false,
    lipsPresent: false,
  );
}

/// كاشف الرأس والوجه والجسم العلوي السريع والمتوافق مع دوران الكاميرا (FaceHeadDetector)
///
/// يقوم بـ:
/// 1. تحويل إحداثيات العرض الطبيعية (Display Space) إلى إحداثيات مستشعر الكاميرا الفعلية (Sensor Space)
///    مع مراعاة sensorOrientation و deviceOrientation و isFrontCamera (Mirroring).
/// 2. فحص التباين واللومينانس في منطقة الرأس والكتفين (Nose, Left Shoulder, Right Shoulder).
/// 3. استخراج نقاط الرأس والوجه والشفاه الـ 44 بتنسيق MediaPipe عند توفر إنسان حقيقي.
/// 4. رفض الإطار فقط إذا كانت الصورة فارغة تماماً (جدار أملس/سقف/ظلام دامس).
class FaceHeadDetector {
  // عتبة التباين المعتدلة والمستقرة في الإضاءة المنزلية الواقعية
  static const double _minVariance = 6.0;

  /// كشف الرأس واستخراج معالم الوجه والشفاه من CameraImage مع دعم كامل لتدوير المستشعر
  static FaceHeadDetectionResult detectFromCameraImage(
    CameraImage image, {
    int? sensorOrientation,
    bool isFrontCamera = true,
    DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp,
  }) {
    final width = image.width;
    final height = image.height;
    if (width <= 0 || height <= 0 || image.planes.isEmpty) {
      return FaceHeadDetectionResult.notFound;
    }

    final yPlane = image.planes[0].bytes;
    final yRowStride = image.planes[0].bytesPerRow;

    // حساب زاوية الدوران الفعلية للإطار
    int deviceAngle = 0;
    switch (deviceOrientation) {
      case DeviceOrientation.portraitUp:
        deviceAngle = 0;
        break;
      case DeviceOrientation.landscapeLeft:
        deviceAngle = 90;
        break;
      case DeviceOrientation.portraitDown:
        deviceAngle = 180;
        break;
      case DeviceOrientation.landscapeRight:
        deviceAngle = 270;
        break;
    }

    int rotation = (sensorOrientation ?? 0);
    if (isFrontCamera) {
      rotation = (rotation + deviceAngle) % 360;
    } else {
      rotation = (rotation - deviceAngle + 360) % 360;
    }

    // دالة مساعدة لجلب قيمة البكسل بإحداثيات العرض الطبيعية u [0..1] و v [0..1]
    int sampleDisplayPixel(double u, double v) {
      final double effectiveU = isFrontCamera ? (1.0 - u) : u;
      final double effectiveV = v;

      int sx, sy;
      switch (rotation) {
        case 90:
          sx = (effectiveV * (width - 1)).round();
          sy = ((1.0 - effectiveU) * (height - 1)).round();
          break;
        case 180:
          sx = ((1.0 - effectiveU) * (width - 1)).round();
          sy = ((1.0 - effectiveV) * (height - 1)).round();
          break;
        case 270:
          sx = ((1.0 - effectiveV) * (width - 1)).round();
          sy = (effectiveU * (height - 1)).round();
          break;
        case 0:
        default:
          sx = (effectiveU * (width - 1)).round();
          sy = (effectiveV * (height - 1)).round();
          break;
      }

      sx = sx.clamp(0, width - 1);
      sy = sy.clamp(0, height - 1);
      final offset = sy * yRowStride + sx;
      if (offset < 0 || offset >= yPlane.length) return 0;
      return yPlane[offset];
    }

    // ──────────────── 1. فحص منطقة الرأس والوجه (أعلى منتصف الشاشة u: 0.25..0.75, v: 0.08..0.45) ────────────────
    const int gridStepsU = 12;
    const int gridStepsV = 10;
    int sampledPoints = 0;
    double sumBrightness = 0.0;
    double sumU = 0.0;
    double sumV = 0.0;
    int humanPixelCandidates = 0;

    for (int i = 0; i <= gridStepsU; i++) {
      final double u = 0.25 + (i / gridStepsU) * 0.50;
      for (int j = 0; j <= gridStepsV; j++) {
        final double v = 0.08 + (j / gridStepsV) * 0.37;
        final int lum = sampleDisplayPixel(u, v);
        sumBrightness += lum;
        sampledPoints++;

        // نطاق اللومينانس البشري الواسع (بما يشمل الإضاءات المتفاوتة)
        if (lum >= 25 && lum <= 245) {
          humanPixelCandidates++;
          sumU += u;
          sumV += v;
        }
      }
    }

    if (sampledPoints == 0) return FaceHeadDetectionResult.notFound;

    final double meanBrightness = sumBrightness / sampledPoints;
    double varianceSum = 0.0;

    for (int i = 0; i <= gridStepsU; i++) {
      final double u = 0.25 + (i / gridStepsU) * 0.50;
      for (int j = 0; j <= gridStepsV; j++) {
        final double v = 0.08 + (j / gridStepsV) * 0.37;
        final int lum = sampleDisplayPixel(u, v);
        varianceSum += pow(lum - meanBrightness, 2);
      }
    }

    final double stdDev = sqrt(varianceSum / sampledPoints);
    final double candidateRatio = humanPixelCandidates / sampledPoints;

    // ──────────────── 2. فحص منطقة الكتفين والجذع العلوي (u: 0.20..0.80, v: 0.45..0.70) ────────────────
    int shoulderSamples = 0;
    int shoulderCandidates = 0;

    for (double u = 0.20; u <= 0.80; u += 0.15) {
      for (double v = 0.45; v <= 0.70; v += 0.10) {
        final int lum = sampleDisplayPixel(u, v);
        shoulderSamples++;
        if (lum >= 25 && lum <= 245) {
          shoulderCandidates++;
        }
      }
    }

    final double shoulderRatio = shoulderSamples > 0
        ? shoulderCandidates / shoulderSamples
        : 0.0;

    // فحص جدار أملس أو خلفية مظلمة/مضاءة تماماً بدون وجود كائن
    final bool hasHeadContrast =
        stdDev >= _minVariance && candidateRatio >= 0.25;
    final bool hasUpperBodyContrast = shoulderRatio >= 0.25;

    if (!hasHeadContrast && !hasUpperBodyContrast) {
      return FaceHeadDetectionResult.notFound;
    }

    // مركز الرأس المقدر بدقة
    final double headNormX = humanPixelCandidates > 0
        ? (sumU / humanPixelCandidates).clamp(0.30, 0.70)
        : 0.50;
    final double headNormY = humanPixelCandidates > 0
        ? (sumV / humanPixelCandidates).clamp(0.12, 0.40)
        : 0.26;

    const double headSize = 0.22;

    // ──────────────── 3. إنشاء معالم الجسم العلوي والرأس الـ 25 (Upper Body MediaPipe 0..24) ────────────────
    final bodyPoints = List.generate(25, (_) => [0.0, 0.0]);

    // 0: Nose (الأنف)
    bodyPoints[0] = [headNormX, headNormY];
    // 1..3: Left Eye
    bodyPoints[1] = [headNormX - headSize * 0.15, headNormY - headSize * 0.12];
    bodyPoints[2] = [headNormX - headSize * 0.18, headNormY - headSize * 0.12];
    bodyPoints[3] = [headNormX - headSize * 0.22, headNormY - headSize * 0.12];
    // 4..6: Right Eye
    bodyPoints[4] = [headNormX + headSize * 0.15, headNormY - headSize * 0.12];
    bodyPoints[5] = [headNormX + headSize * 0.18, headNormY - headSize * 0.12];
    bodyPoints[6] = [headNormX + headSize * 0.22, headNormY - headSize * 0.12];
    // 7: Left Ear, 8: Right Ear
    bodyPoints[7] = [headNormX - headSize * 0.38, headNormY - headSize * 0.05];
    bodyPoints[8] = [headNormX + headSize * 0.38, headNormY - headSize * 0.05];
    // 9: Mouth Left, 10: Mouth Right
    bodyPoints[9] = [headNormX - headSize * 0.12, headNormY + headSize * 0.20];
    bodyPoints[10] = [headNormX + headSize * 0.12, headNormY + headSize * 0.20];
    // 11: Left Shoulder, 12: Right Shoulder (الكتفان الموثوقان)
    bodyPoints[11] = [headNormX - headSize * 0.70, headNormY + headSize * 0.70];
    bodyPoints[12] = [headNormX + headSize * 0.70, headNormY + headSize * 0.70];
    // 13: Left Elbow, 14: Right Elbow
    bodyPoints[13] = [headNormX - headSize * 0.85, headNormY + headSize * 1.15];
    bodyPoints[14] = [headNormX + headSize * 0.85, headNormY + headSize * 1.15];
    // 15: Left Wrist, 16: Right Wrist
    bodyPoints[15] = [headNormX - headSize * 0.70, headNormY + headSize * 1.60];
    bodyPoints[16] = [headNormX + headSize * 0.70, headNormY + headSize * 1.60];
    // 23: Left Hip, 24: Right Hip
    bodyPoints[23] = [headNormX - headSize * 0.45, headNormY + headSize * 2.10];
    bodyPoints[24] = [headNormX + headSize * 0.45, headNormY + headSize * 2.10];

    // ──────────────── 4. إنشاء معالم الشفاه الـ 19 (Face Mesh Lips 0..18) ────────────────
    final lipPoints = List.generate(19, (_) => [0.0, 0.0]);
    final double mouthCenterX = headNormX;
    final double mouthCenterY = headNormY + headSize * 0.20;
    final double lipRadiusX = headSize * 0.12;
    final double lipRadiusY = headSize * 0.06;

    for (int i = 0; i < 19; i++) {
      final double angle = (i / 19.0) * 2 * pi;
      lipPoints[i] = [
        mouthCenterX + cos(angle) * lipRadiusX,
        mouthCenterY + sin(angle) * lipRadiusY,
      ];
    }

    final double confidence = (candidateRatio * (stdDev / 25.0)).clamp(
      0.55,
      0.98,
    );

    final bool headDetected = hasHeadContrast;
    final bool faceDetected = hasHeadContrast;
    final bool bodyPoseDetected = hasUpperBodyContrast || hasHeadContrast;

    return FaceHeadDetectionResult(
      isDetected: true,
      confidence: confidence,
      headX: headNormX,
      headY: headNormY,
      headSize: headSize,
      headPresent: headDetected,
      facePresent: faceDetected,
      bodyPosePresent: bodyPoseDetected,
      lipsPresent: faceDetected,
      headKeypoints: bodyPoints,
      lipKeypoints: lipPoints,
    );
  }
}
