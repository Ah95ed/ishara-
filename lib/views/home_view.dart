import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/controllers/camera_controller.dart';
import 'package:ishara/providers/vision_detection_provider.dart';
import 'package:ishara/views/widgets/body_parts_status_card.dart';
import 'package:ishara/views/widgets/camera_preview_widget.dart';
import 'package:provider/provider.dart';

/// HomeView
/// الشاشة الرئيسية النظيفة المخصصة لكشف الرؤية المباشر (Vision Detection)
/// تعرض الكاميرا في الأعلى، وتحتها مباشرة بطاقة حالة التعرف للأجزاء الـ 6:
/// الشخص، الرأس، الوجه، الشفاه، اليد اليمنى، اليد اليسرى.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  bool _showOverlay = true;
  bool _showNumbers = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final cameraProvider = context.read<CameraProvider>();

      cameraProvider.initializeCamera().then((_) {
        if (mounted && cameraProvider.isReady) {
          cameraProvider.startStream(_onCameraImage);
        }
      });
    });
  }

  /// معالجة كل إطار كاميرا عبر VisionDetectionProvider
  Future<void> _onCameraImage(CameraImage image) async {
    if (!mounted) return;
    try {
      final cameraProvider = context.read<CameraProvider>();
      await cameraProvider.processFrame(image);

      if (!mounted) return;
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
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[HomeView] ⚠️ Error in _onCameraImage: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.visibility_rounded, size: 20),
            ),
            const SizedBox(width: 8),
            const Text(
              '${AppConstants.appName} - كاشف الرؤية',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        actions: [
          Consumer<CameraProvider>(
            builder: (context, cameraProvider, _) {
              return IconButton(
                onPressed: cameraProvider.isSwitchingCamera
                    ? null
                    : () {
                        if (mounted) {
                          cameraProvider.switchCamera();
                        }
                      },
                icon: cameraProvider.isSwitchingCamera
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.flip_camera_ios_rounded),
                tooltip: 'تبديل الكاميرا (أمامية / خلفية)',
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 800;

            if (isWide) {
              return _buildWideLayout(context);
            }
            return _buildNarrowLayout(context);
          },
        ),
      ),
    );
  }

  Widget _buildNarrowLayout(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCameraSection(context),
          const SizedBox(height: 16),
          const BodyPartsStatusCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildCameraSection(context),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          const Expanded(
            flex: 4,
            child: SingleChildScrollView(
              child: BodyPartsStatusCard(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraSection(BuildContext context) {
    return Consumer2<CameraProvider, VisionDetectionProvider>(
      builder: (context, cameraProvider, visionProvider, _) {
        if (cameraProvider.hasError) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.redAccent),
            ),
            child: Center(
              child: Text(
                cameraProvider.errorMessage ?? 'خطأ في الكاميرا',
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          );
        }

        if (!cameraProvider.isReady) {
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

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                CameraPreviewWidget(
                  key: ValueKey(cameraProvider.cameraController),
                  cameraController: cameraProvider.cameraController,
                  visionState: visionProvider.state,
                  showOverlay: _showOverlay,
                  showNumbers: _showNumbers,
                  isStreaming: cameraProvider.isStreaming,
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // زر تبديل إظهار الـ Overlay
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _showOverlay = !_showOverlay;
                            });
                          },
                          icon: Icon(
                            _showOverlay
                                ? Icons.layers_rounded
                                : Icons.layers_clear_rounded,
                            color: _showOverlay ? Colors.greenAccent : Colors.white70,
                            size: 20,
                          ),
                          tooltip: _showOverlay ? 'إخفاء المعالم' : 'إظهار المعالم',
                        ),
                        // زر تبديل إظهار أرقام النقاط (0..20)
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _showNumbers = !_showNumbers;
                            });
                          },
                          icon: Icon(
                            _showNumbers ? Icons.pin_drop : Icons.pin_drop_outlined,
                            color: _showNumbers ? Colors.cyanAccent : Colors.white70,
                            size: 20,
                          ),
                          tooltip: _showNumbers ? 'إخفاء أرقام النقاط' : 'إظهار أرقام النقاط (0..20)',
                        ),
                        // زر إيقاف / استئناف البث
                        IconButton(
                          onPressed: () {
                            cameraProvider.toggleStream(_onCameraImage);
                          },
                          icon: Icon(
                            cameraProvider.isStreaming
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: Colors.white,
                            size: 24,
                          ),
                          tooltip: cameraProvider.isStreaming
                              ? 'إيقاف مؤقت'
                              : 'استئناف',
                        ),
                        // زر تبديل الكاميرا (أمامية / خلفية)
                        IconButton(
                          onPressed: cameraProvider.isSwitchingCamera
                              ? null
                              : () => cameraProvider.switchCamera(),
                          icon: cameraProvider.isSwitchingCamera
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.flip_camera_ios,
                                  color: Colors.white,
                                  size: 20,
                                ),
                          tooltip: 'تبديل الكاميرا',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
