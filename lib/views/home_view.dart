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
/// الواجهة الأصلية البسيطة لتطبيق Ishara:
/// 1. Camera Preview نظيفة بدون أي Debug Overlay
/// 2. زر [ ابدأ الاختبار ]
/// 3. النتيجة مباشرة أسفل الكاميرا (مثال: إعادة)
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
  /// يتم الاحتفاظ بأحدث إطار فقط واستبدال أي إطار معلق سابق
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
      _pendingFrame = null; // تفريغ الإطار المعلق لبدء المعالجة

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
                  const SizedBox(height: 32),

                  // ── 2. [ ابدأ الاختبار ] ──
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: testController.canStartTest
                          ? () => testController.startSimpleTest()
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
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
                            ? 'جارٍ الاختبار...'
                            : 'ابدأ الاختبار',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── 3. النتيجة هنا ──
                  if (testController.displayResult.isNotEmpty)
                    GestureDetector(
                      onLongPress: () async {
                        await testController.copyResult();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم نسخ تقرير الاختبار التشخيصي'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      child: Center(
                        child: Text(
                          testController.displayResult,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
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
