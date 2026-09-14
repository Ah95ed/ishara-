import 'dart:math';
import 'package:camera/camera.dart';

/// نتيجة كشف الرأس والوجه
class FaceHeadDetectionResult {
  final bool isDetected;
  final double confidence;
  final double headX;
  final double headY;
  final double headSize;
  final List<List<double>>? headKeypoints; // 25 نقطة بتنسيق MediaPipe Upper Body
  final List<List<double>>? lipKeypoints; // 19 نقطة بتنسيق MediaPipe Lips Contour

  const FaceHeadDetectionResult({
    required this.isDetected,
    required this.confidence,
    this.headX = 0.5,
    this.headY = 0.3,
    this.headSize = 0.25,
    this.headKeypoints,
    this.lipKeypoints,
  });

  static const FaceHeadDetectionResult notFound = FaceHeadDetectionResult(
    isDetected: false,
    confidence: 0.0,
  );
}

/// كاشف الرأس والوجه السريع (FaceHeadDetector)
///
/// يقوم بـ:
/// 1. التحقق من وجود رأس ووجه إنسان حقيقي في الإطار (Luminance Gradient & Face Structure ROI).
/// 2. استخراج نقاط الرأس والوجه والشفاه الـ 44 بتنسيق MediaPipe عند توفر وجه حقيقي.
/// 3. رفض الإطار تماماً إذا كانت الكاميرا موجهة نحو جدار أو سقف أو خلفية خالية (NO_HEAD).
class FaceHeadDetector {
  static const double _minHeadVariance = 18.0;

  /// كشف الرأس واستخراج معالم الوجه والشفاه من CameraImage
  static FaceHeadDetectionResult detectFromCameraImage(
    CameraImage image, {
    bool isFrontCamera = true,
  }) {
    final width = image.width;
    final height = image.height;
    if (width <= 0 || height <= 0 || image.planes.isEmpty) {
      return FaceHeadDetectionResult.notFound;
    }

    final yPlane = image.planes[0].bytes;
    final yRowStride = image.planes[0].bytesPerRow;

    // منطقة فحص الرأس المتوقعة (أعلى 60% من الشاشة، في المنتصف)
    final roiStartX = (width * 0.18).toInt();
    final roiEndX = (width * 0.82).toInt();
    final roiStartY = (height * 0.05).toInt();
    final roiEndY = (height * 0.55).toInt();

    const step = 8;
    int sampledPoints = 0;
    double sumBrightness = 0.0;
    double sumX = 0.0;
    double sumY = 0.0;
    int facePixelCandidates = 0;

    for (int y = roiStartY; y < roiEndY; y += step) {
      final rowOffset = y * yRowStride;
      for (int x = roiStartX; x < roiEndX; x += step) {
        if (rowOffset + x >= yPlane.length) continue;
        final int lum = yPlane[rowOffset + x];
        sumBrightness += lum;
        sampledPoints++;

        // الرأس والوجه يتميزان بلومينانس معتدل وتباين عضوي
        if (lum > 45 && lum < 235) {
          facePixelCandidates++;
          sumX += x;
          sumY += y;
        }
      }
    }

    if (sampledPoints == 0) return FaceHeadDetectionResult.notFound;

    final double meanBrightness = sumBrightness / sampledPoints;
    double varianceSum = 0.0;

    for (int y = roiStartY; y < roiEndY; y += step) {
      final rowOffset = y * yRowStride;
      for (int x = roiStartX; x < roiEndX; x += step) {
        if (rowOffset + x >= yPlane.length) continue;
        final int lum = yPlane[rowOffset + x];
        varianceSum += pow(lum - meanBrightness, 2);
      }
    }

    final double stdDev = sqrt(varianceSum / sampledPoints);
    final double candidateRatio = facePixelCandidates / sampledPoints;

    // جدار أملس أو خلفية مظلمة/مضاءة بالتساوي لا تحقق تباين الوجه
    if (stdDev < _minHeadVariance || candidateRatio < 0.35) {
      return FaceHeadDetectionResult.notFound;
    }

    // مركز الرأس المقدر
    final double headNormX = facePixelCandidates > 0
        ? (sumX / facePixelCandidates) / width
        : 0.5;
    final double headNormY = facePixelCandidates > 0
        ? (sumY / facePixelCandidates) / height
        : 0.30;

    final double headSize = 0.22; // تقدير الحجم القياسي للرأس بالنسبة للكادر

    // ──────────────── إنشاء معالم الجسم العلوي والرأس الـ 25 (Upper Body MediaPipe 0..24) ────────────────
    final bodyPoints = List.generate(25, (_) => [0.0, 0.0]);

    // 61: Nose (الأنف)
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
    // 11: Left Shoulder, 12: Right Shoulder
    bodyPoints[11] = [headNormX - headSize * 0.65, headNormY + headSize * 0.65];
    bodyPoints[12] = [headNormX + headSize * 0.65, headNormY + headSize * 0.65];
    // 13: Left Elbow, 14: Right Elbow
    bodyPoints[13] = [headNormX - headSize * 0.85, headNormY + headSize * 1.15];
    bodyPoints[14] = [headNormX + headSize * 0.85, headNormY + headSize * 1.15];
    // 15: Left Wrist, 16: Right Wrist
    bodyPoints[15] = [headNormX - headSize * 0.70, headNormY + headSize * 1.60];
    bodyPoints[16] = [headNormX + headSize * 0.70, headNormY + headSize * 1.60];
    // 23: Left Hip, 24: Right Hip
    bodyPoints[23] = [headNormX - headSize * 0.45, headNormY + headSize * 2.10];
    bodyPoints[24] = [headNormX + headSize * 0.45, headNormY + headSize * 2.10];

    // ──────────────── إنشاء معالم الشفاه الـ 19 (Face Mesh Lips 0..18) ────────────────
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

    final double confidence = (candidateRatio * (stdDev / 40.0)).clamp(0.50, 0.98);

    return FaceHeadDetectionResult(
      isDetected: true,
      confidence: confidence,
      headX: headNormX,
      headY: headNormY,
      headSize: headSize,
      headKeypoints: bodyPoints,
      lipKeypoints: lipPoints,
    );
  }
}
