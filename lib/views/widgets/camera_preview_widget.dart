import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:ishara/models/landmarks_model.dart';

/// واجهة عرض الكاميرا النظيفة والمخصصة لترجمة لغة الإشارة
/// تعرض بث الكاميرا بوضوح تام، مع إبراز الإشارة والحرف العربي المستقر فور التعرف عليه
class CameraPreviewWidget extends StatelessWidget {
  final CameraController? cameraController;
  final HandLandmarks? landmarks;
  final bool showLandmarks;
  final bool isStreaming;
  final bool isHandDetected;
  final String? activeSignLabel;
  final bool isStable;

  const CameraPreviewWidget({
    super.key,
    this.cameraController,
    this.landmarks,
    this.showLandmarks = false, // معطل افتراضياً بناءً على طلب المستخدم لعدم تشتيت الرؤية
    this.isStreaming = false,
    this.isHandDetected = false,
    this.activeSignLabel,
    this.isStable = false,
  });

  bool get _canShowSkeleton =>
      showLandmarks &&
      isHandDetected &&
      landmarks != null &&
      landmarks!.landmarks.length == 21;

  @override
  Widget build(BuildContext context) {
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return Container(
        height: 340,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text(
                'جارٍ تهيئة الكاميرا...',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    final aspectRatio = cameraController!.value.aspectRatio;
    final isFrontCamera =
        cameraController!.description.lensDirection == CameraLensDirection.front;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. طبقة بث الكاميرا النقي
            CameraPreview(cameraController!),

            // 2. رسم النقاط إذا طُلبت صراحة (معطلة افتراضياً)
            if (_canShowSkeleton)
              Positioned.fill(
                child: CustomPaint(
                  painter: HandLandmarksPainter(
                    landmarks: landmarks!,
                    isFrontCamera: isFrontCamera,
                  ),
                ),
              ),

            // 3. مؤشر خفيف عند رصد اليد أعلى اليمين
            Positioned(
              top: 14,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isHandDetected ? Colors.greenAccent : Colors.white24,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: isHandDetected ? Colors.greenAccent : Colors.white38,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isHandDetected ? 'تم رصد اليد' : 'وجّه يدك للكاميرا',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 4. عرض الحرف أو الإشارة الفورية الكبيرة والمستقرة (Fast Path)
            if (activeSignLabel != null && activeSignLabel!.isNotEmpty)
              Positioned(
                bottom: 24,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: isStable ? Colors.greenAccent : Colors.amberAccent,
                        width: 2.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isStable ? Colors.greenAccent : Colors.amberAccent)
                              .withValues(alpha: 0.35),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: isStable ? Colors.greenAccent : Colors.amberAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          activeSignLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        if (isStable) ...[
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.greenAccent,
                            size: 22,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// رسام معالم اليد (اختياري فقط إذا تم تمكينه)
class HandLandmarksPainter extends CustomPainter {
  final HandLandmarks landmarks;
  final bool isFrontCamera;

  HandLandmarksPainter({
    required this.landmarks,
    this.isFrontCamera = false,
  });

  static const List<List<int>> connections = [
    [0, 1], [1, 2], [2, 3], [3, 4],
    [0, 5], [5, 6], [6, 7], [7, 8],
    [5, 9], [9, 10], [10, 11], [11, 12],
    [9, 13], [13, 14], [14, 15], [15, 16],
    [13, 17], [17, 18], [18, 19], [19, 20],
    [0, 17],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final lms = landmarks.landmarks;
    if (lms.length < 21) return;

    final linePaint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (final conn in connections) {
      final p1 = lms[conn[0]];
      final p2 = lms[conn[1]];
      final x1 = isFrontCamera ? (1.0 - p1.x) * size.width : p1.x * size.width;
      final y1 = p1.y * size.height;
      final x2 = isFrontCamera ? (1.0 - p2.x) * size.width : p2.x * size.width;
      final y2 = p2.y * size.height;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
    }

    for (final pt in lms) {
      final x = isFrontCamera ? (1.0 - pt.x) * size.width : pt.x * size.width;
      final y = pt.y * size.height;
      canvas.drawCircle(Offset(x, y), 4.0, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant HandLandmarksPainter oldDelegate) => true;
}
