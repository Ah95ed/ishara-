import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:ishara/models/body_parts_detection_state.dart';
import 'package:ishara/views/widgets/vision_landmarks_overlay_painter.dart';

/// CameraPreviewWidget
/// واجهة عرض الكاميرا مع Overlay المعالم الحقيقية اللحظية (Vision Landmarks)
/// تدعم رسم الهيكل العظمي للأيدي (21 نقطة) وأرقامها، والشفاه (19 نقطة)، والوجه والجسم.
class CameraPreviewWidget extends StatelessWidget {
  final CameraController? cameraController;
  final VisionLandmarksState? visionState;
  final bool showOverlay;
  final bool showNumbers;
  final bool isStreaming;

  const CameraPreviewWidget({
    super.key,
    this.cameraController,
    this.visionState,
    this.showOverlay = true,
    this.showNumbers = true,
    this.isStreaming = false,
  });

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
            // 1. طبقة بث الكاميرا المباشر
            CameraPreview(cameraController!),

            // 2. طبقة رسم المعالم الحقيقية اللحظية فوق الكاميرا
            if (showOverlay && visionState != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: VisionLandmarksOverlayPainter(
                    state: visionState!,
                    isFrontCamera: isFrontCamera,
                    showNumbers: showNumbers,
                    showHands: true,
                    showFaceAndLips: true,
                    showPose: true,
                    showTelemetry: true,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
