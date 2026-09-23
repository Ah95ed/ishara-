import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/controllers/camera_controller.dart';
import 'package:ishara/controllers/ishara_test_controller.dart';
import 'package:ishara/providers/vision_detection_provider.dart';
import 'package:ishara/views/widgets/camera_preview_widget.dart';
import 'package:provider/provider.dart';

/// HomeView
/// الواجهة البسيطة لتطبيق Ishara مع نظام التتبع والتشخيص الشامل:
/// 1. Camera Preview نظيفة بدون أي Debug Overlay
/// 2. زر [ ابدأ الاختبار ] مع عداد فريمات داخلي أثناء الجمع
/// 3. النتيجة مباشرة أسفل الكاميرا
/// 4. زر نسخ تقرير التتبع الكامل بنقرة واحدة لتمكين المطور من لصقه مباشرة
/// 5. زر استعراض تفاصيل المراحل العشر لتشخيص أي مشكلة فوراً
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  // أحدث فريم معلق (Latest Pending Frame Only - لمنع تراكم الطوابير)
  CameraImage? _pendingFrame;
  bool _isProcessingFrame = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initCamera();
    });
  }

  void _initCamera() {
    final cameraProvider = context.read<CameraProvider>();
    cameraProvider.initializeCamera().then((_) {
      if (mounted && cameraProvider.isReady) {
        cameraProvider.startStream(_onCameraImage);
      }
    });
  }

  /// استقبال إطارات الكاميرا: Latest Frame Only
  void _onCameraImage(CameraImage image) {
    if (!mounted) return;

    _pendingFrame = image;
    if (!_isProcessingFrame) {
      _processPendingFrames();
    }
  }

  Future<void> _processPendingFrames() async {
    if (_isProcessingFrame) return;
    _isProcessingFrame = true;

    while (_pendingFrame != null && mounted) {
      final image = _pendingFrame!;
      _pendingFrame = null;

      try {
        final cameraProvider = context.read<CameraProvider>();
        await cameraProvider.processFrame(image);

        if (!mounted) break;
        final visionProvider = context.read<VisionDetectionProvider>();
        final isFront =
            cameraProvider.cameraController?.description.lensDirection ==
            CameraLensDirection.front;
        final sensorOrientation =
            cameraProvider.cameraController?.description.sensorOrientation;
        final deviceOrientation =
            cameraProvider.cameraController?.value.deviceOrientation ??
            DeviceOrientation.portraitUp;

        await visionProvider.processFrame(
          image,
          sensorOrientation: sensorOrientation,
          isFrontCamera: isFront,
          deviceOrientation: deviceOrientation,
        );

        if (!mounted) break;
        final latestId =
            visionProvider.state.ringBufferStatus?.latestFrameSequenceId;
        if (latestId != null) {
          context.read<IsharaTestController>().onFrameProcessed(latestId);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[HomeView] ⚠️ Error in _processPendingFrames: $e');
        }
      }
    }

    _isProcessingFrame = false;
  }

  /// تبديل الكاميرا بأمان وتصفير بيانات الجلسة الحالية
  Future<void> _onSwitchCamera() async {
    _pendingFrame = null;
    _isProcessingFrame = false;

    final testController = context.read<IsharaTestController>();
    testController.resetTest();

    final cameraProvider = context.read<CameraProvider>();
    await cameraProvider.switchCamera();
  }

  /// عرض نافذة تفاصيل التتبع والتشخيص للمراحل العشر
  void _showDiagnosticsModal(
    BuildContext context,
    IsharaTestController testController,
  ) {
    final tracer = testController.tracer;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.40,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ListView(
                controller: scrollController,
                children: [
                  // شريط السحب العلوي
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // عنوان النافذة وزر النسخ السريع
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'تفاصيل التتبع والتشخيص',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () async {
                          await testController.copyFullTraceReport();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم نسخ تقرير التتبع الكامل ✓'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        tooltip: 'نسخ التقرير',
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // 1. صحة النظام والكواشف
                  _buildSectionCard(
                    title: '1. جاهزية النظام والكواشف',
                    isPass:
                        tracer.cameraReady &&
                        tracer.poseDetectorReady &&
                        tracer.faceMeshReady &&
                        tracer.handDetectorReady &&
                        tracer.tfliteReady &&
                        tracer.vocabReady,
                    children: [
                      _buildInfoRow('الكاميرا', tracer.cameraReady ? 'جاهزة ✅' : 'غير جاهزة ❌'),
                      _buildInfoRow('كاشف الوضعية (Pose)', tracer.poseDetectorReady ? 'جاهز ✅' : 'فشل ❌'),
                      _buildInfoRow('كاشف الوجه والشفاه (FaceMesh)', tracer.faceMeshReady ? 'جاهز ✅' : 'فشل ❌'),
                      _buildInfoRow('كاشف الأيدي (MediaPipe Hands)', tracer.handDetectorReady ? 'جاهز ✅' : 'فشل ❌'),
                      _buildInfoRow('محرك الموديل (TFLite)', tracer.tfliteReady ? 'جاهز ✅ (${tracer.modelSizeMb.toStringAsFixed(1)} MB)' : 'خطأ ❌ (${tracer.tfliteState})'),
                      if (tracer.tfliteInitError != null)
                        _buildInfoRow('خطأ الموديل', tracer.tfliteInitError!, isError: true),
                      _buildInfoRow('قاموس الكلمات (Vocab)', tracer.vocabReady ? 'تم التحميل ✅ (${tracer.vocabCount} كلمة)' : 'فشل ❌'),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 2. تدفق الكاميرا
                  _buildSectionCard(
                    title: '2. تدفق الكاميرا اللحظي',
                    isPass: tracer.liveFps > 5.0,
                    children: [
                      _buildInfoRow('معدل الفريمات (FPS)', '${tracer.liveFps.toStringAsFixed(1)} FPS'),
                      _buildInfoRow('الفريمات المستلمة', '${tracer.totalCameraFramesReceived}'),
                      _buildInfoRow('الفريمات المسقطة', '${tracer.totalCameraFramesDropped}'),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 3 & 4. المعالم وكشف الأجزاء
                  _buildSectionCard(
                    title: '3 & 4. كشف المعالم والأيدي (86 نقطة)',
                    isPass: tracer.latestLandmarks.personDetected,
                    children: [
                      _buildInfoRow('كشف الشخص', tracer.latestLandmarks.personDetected ? 'موجود ✅' : 'غير مكتشف ⚠️'),
                      _buildInfoRow('اليد اليمنى', '${tracer.latestLandmarks.rightHandPoints} / 21 نقطة ${tracer.latestLandmarks.rightHandPoints >= 10 ? "✅" : "⚠️"}'),
                      _buildInfoRow('اليد اليسرى', '${tracer.latestLandmarks.leftHandPoints} / 21 نقطة ${tracer.latestLandmarks.leftHandPoints >= 10 ? "✅" : "⚠️"}'),
                      _buildInfoRow('الشفاه', '${tracer.latestLandmarks.lipsPoints} / 19 نقطة'),
                      _buildInfoRow('النقاط الملتقطة / المعوضة', '${tracer.latestLandmarks.rawDetectedCount} / ${tracer.latestLandmarks.imputedCount}'),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 5. الـ Ring Buffer
                  _buildSectionCard(
                    title: '5. مخزن الإطارات الدائري (Ring Buffer)',
                    isPass: tracer.ringBufferCount >= 128 || testController.isCollecting,
                    children: [
                      _buildInfoRow('الفريمات المجمعة', '${tracer.ringBufferCount} / 128 (${(tracer.ringBufferCount * 100.0 / 128).clamp(0, 100).toStringAsFixed(0)}%)'),
                      _buildInfoRow('فريمات مضافة في الجلسة', '${tracer.ringBufferFramesAdded}'),
                      _buildInfoRow('فريمات تم تخطيها لغياب الشخص', '${tracer.ringBufferFramesSkippedNoPerson}'),
                      _buildInfoRow('فريمات مكررة مرفوضة', '${tracer.ringBufferDuplicatesRejected}'),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 6. مصفوفة الإدخال [1, 128, 86, 2]
                  _buildSectionCard(
                    title: '6. مصفوفة الإدخال للموديل [1, 128, 86, 2]',
                    isPass: tracer.modelInputTelemetry != null && tracer.modelInputTelemetry!.nanCount == 0,
                    children: [
                      if (tracer.modelInputTelemetry != null) ...[
                        _buildInfoRow('أبعاد المصفوفة', '${tracer.modelInputTelemetry!.shape} (22,016 float)'),
                        _buildInfoRow('قيم NaN', '${tracer.modelInputTelemetry!.nanCount} ${tracer.modelInputTelemetry!.nanCount == 0 ? "✅" : "❌"}'),
                        _buildInfoRow('قيم Infinity', '${tracer.modelInputTelemetry!.infCount} ${tracer.modelInputTelemetry!.infCount == 0 ? "✅" : "❌"}'),
                        _buildInfoRow('نطاق القيم (Min..Max)', '[${tracer.modelInputTelemetry!.minVal.toStringAsFixed(3)} .. ${tracer.modelInputTelemetry!.maxVal.toStringAsFixed(3)}]'),
                        _buildInfoRow('متوسط القيم (Mean)', tracer.modelInputTelemetry!.meanVal.toStringAsFixed(4)),
                      ] else ...[
                        _buildInfoRow('الحالة', 'في انتظار اكتمال 128 إطاراً'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 7. استنتاج TFLite
                  _buildSectionCard(
                    title: '7. استنتاج TFLite [1, 29, 684]',
                    isPass: tracer.modelOutputTelemetry != null && !tracer.hasError,
                    children: [
                      if (tracer.modelOutputTelemetry != null) ...[
                        _buildInfoRow('زمن الاستنتاج', '${tracer.modelOutputTelemetry!.inferenceTimeMs} ms'),
                        _buildInfoRow('أبعاد المخرجات', '${tracer.modelOutputTelemetry!.outputShape}'),
                        _buildInfoRow('نسبة الفراغ Blank 0', '${tracer.modelOutputTelemetry!.blankCount} / 29 خطوة'),
                        _buildInfoRow('الفئات المكتشفة', '${tracer.modelOutputTelemetry!.uniqueNonBlankClasses}'),
                        _buildInfoRow('Raw Argmax (29)', '${tracer.modelOutputTelemetry!.rawArgmax.take(15).toList()}...'),
                      ] else ...[
                        _buildInfoRow('الحالة', 'لم يتم التنفيذ بعد'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 8 & 9. CTC والقاموس
                  _buildSectionCard(
                    title: '8 & 9. فك تشفير CTC والقاموس',
                    isPass: tracer.modelOutputTelemetry != null && tracer.modelOutputTelemetry!.ctcDecodedIds.isNotEmpty,
                    children: [
                      if (tracer.modelOutputTelemetry != null) ...[
                        _buildInfoRow('رموز CTC المستخرجة', '${tracer.modelOutputTelemetry!.ctcDecodedIds}'),
                        _buildInfoRow('الكلمات المقابلة (Glosses)', '${tracer.modelOutputTelemetry!.glosses}'),
                        _buildInfoRow('النتيجة النهائية', '"${tracer.finalGlossResult}"'),
                      ] else ...[
                        _buildInfoRow('الحالة', 'في الانتظار'),
                      ],
                    ],
                  ),

                  // 10. الخطأ إن وجد
                  if (tracer.hasError) ...[
                    const SizedBox(height: 12),
                    _buildSectionCard(
                      title: '10. تفاصيل الخطأ والاستثناء (Exception)',
                      isPass: false,
                      children: [
                        _buildInfoRow('المرحلة المسببة', tracer.errorStage ?? 'غير محددة', isError: true),
                        _buildInfoRow('رسالة الخطأ', tracer.errorMessage ?? '', isError: true),
                        if (tracer.errorStackTrace != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                tracer.errorStackTrace!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: Colors.redAccent,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 24),
                  // زر النسخ الكبير في نهاية التقرير
                  ElevatedButton.icon(
                    onPressed: () async {
                      await testController.copyFullTraceReport();
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم نسخ تقرير التتبع الشامل بالكامل ✓'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_all_rounded),
                    label: const Text('نسخ التقرير الكامل للحافظة'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSectionCard({
    required String title,
    required bool isPass,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isPass
            ? Colors.green.withValues(alpha: 0.05)
            : Colors.red.withValues(alpha: 0.05),
        border: Border.all(
          color: isPass
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPass ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 18,
                color: isPass ? Colors.green : Colors.redAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isPass ? Colors.green.shade800 : Colors.redAccent.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: isError ? Colors.redAccent : Colors.black87,
                fontWeight: isError ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          AppConstants.appName,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
        actions: [
          // زر تبديل الكاميرا (Front <-> Back)
          Consumer<CameraProvider>(
            builder: (context, cameraProvider, _) {
              return IconButton(
                onPressed:
                    cameraProvider.isSwitchingCamera ? null : _onSwitchCamera,
                icon: cameraProvider.isSwitchingCamera
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.flip_camera_ios_rounded),
                tooltip: 'تبديل الكاميرا',
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer2<CameraProvider, IsharaTestController>(
          builder: (context, cameraProvider, testController, _) {
            final bool isFailed = testController.isFailed;
            final bool hasResult = testController.displayResult.isNotEmpty;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 1. CAMERA PREVIEW ──
                  Container(
                    constraints: const BoxConstraints(maxHeight: 460),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CameraPreviewWidget(
                      cameraController: cameraProvider.cameraController,
                      showOverlay: false,
                      showNumbers: false,
                      isStreaming: cameraProvider.isStreaming,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── 2. [ ابدأ الاختبار ] ──
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: testController.canStartTest
                          ? () => testController.startSimpleTest()
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isFailed
                            ? Colors.redAccent.shade700
                            : Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        disabledBackgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.5),
                        disabledForegroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary.withValues(alpha: 0.8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        testController.isTesting
                            ? 'جارٍ الاختبار (${testController.collectedFrames} / 128)...'
                            : (isFailed ? 'إعادة الاختبار' : 'ابدأ الاختبار'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── 3. النتيجة أو رسالة الخطأ ──
                  if (hasResult)
                    Center(
                      child: Text(
                        testController.displayResult,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isFailed ? 22 : 32,
                          fontWeight: FontWeight.bold,
                          color: isFailed
                              ? Colors.redAccent.shade700
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),

                  // ── 4. أزرار التتبع والتشخيص المباشر ──
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await testController.copyFullTraceReport();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Row(
                                children: [
                                  Icon(Icons.check_circle_rounded,
                                      color: Colors.greenAccent),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'تم نسخ تقرير التتبع الكامل للحافظة ✓ (يمكنك لصقه في المحادثة)',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              duration: Duration(seconds: 4),
                              backgroundColor: Color(0xFF1E1E2E),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_all_rounded, size: 22),
                      label: const Text(
                        'نسخ تقرير التتبع الكامل (Trace Report)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isFailed
                            ? Colors.redAccent.shade700
                            : Theme.of(context).colorScheme.secondary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // زر استعراض تفاصيل المراحل
                  Center(
                    child: TextButton.icon(
                      onPressed: () =>
                          _showDiagnosticsModal(context, testController),
                      icon: const Icon(Icons.analytics_outlined, size: 20),
                      label: const Text(
                        'استعراض تفاصيل مراحل المعالجة (10 مراحل)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
