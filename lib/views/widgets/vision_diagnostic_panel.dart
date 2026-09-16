import 'package:flutter/material.dart';
import 'package:ishara/controllers/camera_controller.dart';
import 'package:ishara/services/diagnostics/diagnostic_models.dart';
import 'package:ishara/services/diagnostics/ishara_diagnostic_service.dart';
import 'package:provider/provider.dart';

/// VisionDiagnosticPanel
/// لوحة التشخيص المباشرة لخط رؤية إشارة (Vision Pipeline Diagnostics).
/// في المرحلة 1، تركز حصرياً على استقرار الكاميرا وتدفق الإطارات ومواصفات الرؤية.
class VisionDiagnosticPanel extends StatelessWidget {
  const VisionDiagnosticPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CameraProvider>(
      builder: (context, cameraProvider, _) {
        final diagService = IsharaDiagnosticService();
        final cameraData = diagService.camera;

        final bool isRunning = cameraProvider.isStreaming &&
            cameraData.status == DiagnosticStageStatus.pass;
        final String statusIcon = isRunning ? '✅' : (cameraProvider.hasError ? '❌' : '⏳');
        final String statusText = isRunning
            ? 'Running — ${cameraProvider.currentFps.toStringAsFixed(1)} FPS'
            : (cameraProvider.hasError
                ? (cameraData.errorCode ?? 'FAIL')
                : (cameraProvider.isReady ? 'Ready' : 'Initializing...'));

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isRunning
                  ? Colors.greenAccent.withValues(alpha: 0.35)
                  : Colors.amberAccent.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── شريط رأس المرحلة الأولى: CAMERA ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isRunning
                              ? Colors.green.withValues(alpha: 0.2)
                              : Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.videocam_rounded,
                          color: isRunning ? Colors.greenAccent : Colors.amberAccent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المرحلة 1: فحص الكاميرا',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Vision Pipeline — Stage 1 (Camera Only)',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isRunning
                          ? Colors.greenAccent.withValues(alpha: 0.15)
                          : Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isRunning ? Colors.greenAccent : Colors.redAccent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          statusIcon,
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: isRunning ? Colors.greenAccent : Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 14),

              // ── شبكة المقاييس الأساسية للمرحلة 1 ──
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildMetricCard(
                    label: 'FPS الحقيقي',
                    value: '${cameraProvider.currentFps.toStringAsFixed(1)} FPS',
                    icon: Icons.speed_rounded,
                    isHighlight: true,
                    isPass: cameraProvider.currentFps >= 10.0,
                  ),
                  _buildMetricCard(
                    label: 'دقة الإطار (Resolution)',
                    value: cameraProvider.imageWidth > 0
                        ? '${cameraProvider.imageWidth} × ${cameraProvider.imageHeight}'
                        : '0 × 0',
                    icon: Icons.aspect_ratio_rounded,
                    isPass: cameraProvider.imageWidth > 0,
                  ),
                  _buildMetricCard(
                    label: 'صيغة الصورة (Format)',
                    value: cameraProvider.imageFormat.toUpperCase(),
                    icon: Icons.image_outlined,
                    isPass: cameraProvider.imageFormat.toLowerCase().contains('yuv') ||
                        cameraProvider.imageFormat.toLowerCase().contains('bgra'),
                  ),
                  _buildMetricCard(
                    label: 'العدسة (Lens)',
                    value: cameraProvider.isFrontCamera ? 'Front (أمامية)' : 'Back (خلفية)',
                    icon: Icons.camera_front_rounded,
                    isPass: true,
                  ),
                  _buildMetricCard(
                    label: 'Preview Rotation',
                    value: '${cameraProvider.previewRotation}°',
                    icon: Icons.screen_rotation_rounded,
                    isPass: cameraProvider.previewRotation % 90 == 0,
                  ),
                  _buildMetricCard(
                    label: 'Detector Rotation',
                    value: '${cameraProvider.detectorRotation}°',
                    icon: Icons.rotate_right_rounded,
                    isPass: cameraProvider.detectorRotation % 90 == 0,
                  ),
                ],
              ),

              // ── معلومات المعالجة وإسقاط الفريمات ──
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'الإطارات: ${cameraProvider.processedFramesCount} معالجة | ${cameraProvider.droppedFramesCount} مستبعدة',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      'Latency: ${cameraProvider.lastProcessingTimeMs.toStringAsFixed(1)} ms',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),

              // ── تنبيه خطأ الكاميرا إن وُجد ──
              if (cameraData.errorCode != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${cameraData.errorCode}: ${cameraData.errorMessage ?? "خطأ في الكاميرا"}',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── تنبيه حالة الكواشف للمرحلة 1 ──
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.amberAccent, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'المرحلة 1 نشطة: الكواشف معطلة عمداً للتأكد من ثبات واستقرار تدفق الكاميرا و FPS.',
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required IconData icon,
    bool isHighlight = false,
    bool isPass = true,
  }) {
    return Container(
      width: 155,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlight
              ? (isPass ? Colors.greenAccent : Colors.redAccent)
              : Colors.white12,
          width: isHighlight ? 1.2 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: isHighlight
                    ? (isPass ? Colors.greenAccent : Colors.redAccent)
                    : Colors.white54,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: isHighlight
                  ? (isPass ? Colors.greenAccent : Colors.redAccent)
                  : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
