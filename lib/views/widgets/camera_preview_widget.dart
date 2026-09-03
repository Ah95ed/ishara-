import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:ishara/models/landmarks_model.dart';

/// واجهة عرض الكاميرا مع رسم معالم اليد
///
/// RULE:
///   - لا يُرسم أي شيء إلا إذا:
///     isHandDetected == true AND landmarks != null AND landmarks.length == 21
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
    this.showLandmarks = true,
    this.isStreaming = false,
    this.isHandDetected = false,
    this.activeSignLabel,
    this.isStable = false,
  });

  bool get _canShowSkeleton =>
      isHandDetected &&
      showLandmarks &&
      landmarks != null &&
      landmarks!.landmarks.length == 21;

  @override
  Widget build(BuildContext context) {
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return Container(
        height: 320,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('جارٍ تهيئة الكاميرا...'),
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
            // 1. طبقة الكاميرا
            CameraPreview(cameraController!),

            // 2. رسم الـ 21 نقطة فوق مفاصل اليد
            if (_canShowSkeleton)
              Positioned.fill(
                child: CustomPaint(
                  painter: HandLandmarksPainter(
                    landmarks: landmarks!,
                    isFrontCamera: isFrontCamera,
                  ),
                ),
              ),

            // 3. إطار التوجيه المركزي
            Center(
              child: Container(
                width: 210,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _canShowSkeleton
                        ? Colors.greenAccent
                        : Colors.white.withValues(alpha: 0.35),
                    width: _canShowSkeleton ? 2.5 : 1.5,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _canShowSkeleton
                            ? '✓ Hands: ${landmarks?.detectedHandsCount ?? 1} | 21 Landmarks'
                            : 'Hands: 0 — وجّه يدك هنا',
                        style: TextStyle(
                          color: _canShowSkeleton
                              ? Colors.greenAccent
                              : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 4. شارة الحالة أعلى اليسار
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _canShowSkeleton ? Colors.greenAccent : Colors.white24,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _canShowSkeleton ? Colors.greenAccent : Colors.white38,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _canShowSkeleton
                          ? 'Hands: ${landmarks?.detectedHandsCount ?? 1} | 21 LMs'
                          : 'Hands: 0',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 5. إشعار أسفل الشاشة عند رصد اليد
            if (_canShowSkeleton)
              Positioned(
                bottom: 14,
                left: 16,
                right: 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.greenAccent, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.greenAccent.withValues(alpha: 0.30),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: Colors.greenAccent, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '✓ تم رصد اليد — ${(landmarks!.confidence * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 6. الإشارة المكتشفة الفورية تحت الكاميرا (Fast Path)
            if (activeSignLabel != null && activeSignLabel!.isNotEmpty)
              Positioned(
                bottom: 58,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isStable ? Colors.greenAccent : Colors.amberAccent,
                        width: 1.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isStable ? Colors.greenAccent : Colors.amberAccent)
                              .withValues(alpha: 0.25),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: isStable ? Colors.greenAccent : Colors.amberAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          activeSignLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (isStable) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
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

/// راسم معالم اليد الـ 21 نقطة باستخدام إحداثيات normalized [0..1]
class HandLandmarksPainter extends CustomPainter {
  final HandLandmarks landmarks;
  final bool isFrontCamera;

  const HandLandmarksPainter({
    required this.landmarks,
    this.isFrontCamera = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final lm = landmarks.landmarks;
    if (lm.length != 21) return;

    double px(double normX) {
      final x = isFrontCamera ? 1.0 - normX : normX;
      return x * size.width;
    }

    double py(double normY) => normY * size.height;

    // ـ الخطوط بين المفاصل ـ
    const fingerConns = <List<int>>[
      [0, 1], [1, 2], [2, 3], [3, 4],       // إبهام
      [0, 5], [5, 6], [6, 7], [7, 8],       // سبابة
      [0, 9], [9, 10], [10, 11], [11, 12],  // وسطى
      [0, 13], [13, 14], [14, 15], [15, 16],// بنصر
      [0, 17], [17, 18], [18, 19], [19, 20],// خنصر
      [5, 9], [9, 13], [13, 17],            // راحة اليد
    ];

    final bonePaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    for (final conn in fingerConns) {
      final p1 = lm[conn[0]];
      final p2 = lm[conn[1]];
      canvas.drawLine(
        Offset(px(p1.x), py(p1.y)),
        Offset(px(p2.x), py(p2.y)),
        bonePaint,
      );
    }

    // ـ النقاط ـ
    final borderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final wristPaint = Paint()
      ..color = const Color(0xFFFF1744)
      ..style = PaintingStyle.fill;

    final tipPaint = Paint()
      ..color = const Color(0xFFFFD600)
      ..style = PaintingStyle.fill;

    final jointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 21; i++) {
      final pt = lm[i];
      final offset = Offset(px(pt.x), py(pt.y));

      final Paint fillPaint;
      final double radius;

      if (i == 0) {
        fillPaint = wristPaint;
        radius = 7.0;
      } else if (i == 4 || i == 8 || i == 12 || i == 16 || i == 20) {
        fillPaint = tipPaint;
        radius = 6.0;
      } else {
        fillPaint = jointPaint;
        radius = 4.5;
      }

      canvas.drawCircle(offset, radius, fillPaint);
      canvas.drawCircle(offset, radius, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant HandLandmarksPainter old) {
    if (old.isFrontCamera != isFrontCamera) return true;
    if (old.landmarks.landmarks.length != landmarks.landmarks.length) return true;
    if (old.landmarks.frameId != landmarks.frameId) return true;
    return false;
  }
}
