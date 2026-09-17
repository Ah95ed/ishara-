import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:ishara/models/body_parts_detection_state.dart';
import 'package:ishara/views/widgets/vision_landmarks_overlay_painter.dart';

/// CameraPreviewWidget
/// واجهة عرض الكاميرا مع دمج طبقة الـ Overlay بدقة متطابقة Pixel-Perfect
/// تضع الـ Overlay مباشرة كـ child لـ CameraPreview لضمان تطابق الأبعاد والـ Stack بنسبة 100%.
class CameraPreviewWidget extends StatelessWidget {
  final CameraController? cameraController;
  final VisionLandmarksState? visionState;
  final bool showOverlay;
  final bool showNumbers;
  final bool calibrationMode;
  final bool isStreaming;

  const CameraPreviewWidget({
    super.key,
    this.cameraController,
    this.visionState,
    this.showOverlay = true,
    this.showNumbers = true,
    this.calibrationMode = false,
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

    final rawRatio = cameraController!.value.aspectRatio;
    // ضبط نسبة العرض القائمة (Portrait Aspect Ratio) لمنع أي تشويه أو مساحات سوداء
    final previewAspectRatio = rawRatio < 1.0 ? rawRatio : (1.0 / rawRatio);

    final isFrontCamera =
        cameraController!.description.lensDirection == CameraLensDirection.front;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: previewAspectRatio,
        child: CameraPreview(
          cameraController!,
          // تمرير الـ Overlay كـ child مباشر داخل نفس Stack الكاميرا الداخلي
          child: (showOverlay && visionState != null)
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    return CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: VisionLandmarksOverlayPainter(
                        state: visionState!,
                        isFrontCamera: isFrontCamera,
                        showNumbers: showNumbers,
                        showHands: true,
                        showFaceAndLips: true,
                        showPose: true,
                        showTelemetry: true,
                        calibrationMode: calibrationMode,
                      ),
                    );
                  },
                )
              : null,
        ),
      ),
    );
  }
}
