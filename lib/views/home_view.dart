import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/controllers/camera_controller.dart';
import 'package:ishara/controllers/gloss_controller.dart';
import 'package:ishara/controllers/sign_controller.dart';
import 'package:ishara/services/temporal_stabilizer.dart';
import 'package:ishara/views/widgets/camera_preview_widget.dart';
import 'package:ishara/views/widgets/hand_landmarks_debug_panel.dart';
import 'package:provider/provider.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
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

  Future<void> _onCameraImage(CameraImage image) async {
    if (!mounted) return;
    final cameraProvider = context.read<CameraProvider>();
    await cameraProvider.processFrame(image);
    if (!mounted) return;

    final signProvider = context.read<SignProvider>();
    if (cameraProvider.isRealHand && cameraProvider.latestLandmarks != null) {
      await signProvider.processLandmarks(cameraProvider.latestLandmarks);
    } else {
      await signProvider.processLandmarks(null);
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
              child: const Icon(Icons.pan_tool_rounded, size: 20),
            ),
            const SizedBox(width: 8),
            const Text(
              '${AppConstants.appName} - مترجم لغة الإشارة',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              if (mounted) {
                context.read<CameraProvider>().switchCamera();
              }
            },
            icon: const Icon(Icons.flip_camera_ios_rounded),
            tooltip: 'تبديل الكاميرا (أمامية / خلفية)',
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
          const SizedBox(height: 12),
          _buildTranslationSection(context),
          const SizedBox(height: 12),
          _buildDebugPanelSection(context),
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
            flex: 5,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildCameraSection(context),
                  const SizedBox(height: 12),
                  _buildTranslationSection(context),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              child: _buildDebugPanelSection(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraSection(BuildContext context) {
    return Consumer2<CameraProvider, GlossController>(
      builder: (context, cameraProvider, glossController, _) {
        if (cameraProvider.hasError) {
          return _ErrorWidget(message: cameraProvider.errorMessage ?? '');
        }
        if (!cameraProvider.isReady) {
          return const _LoadingWidget();
        }
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                CameraPreviewWidget(
                  key: ValueKey(cameraProvider.cameraController),
                  cameraController: cameraProvider.cameraController,
                  landmarks: cameraProvider.isRealHand
                      ? cameraProvider.latestLandmarks
                      : null,
                  isHandDetected: cameraProvider.isRealHand,
                  isStreaming: cameraProvider.isStreaming,
                  activeSignLabel: glossController.currentSign,
                  isStable: glossController.stabilityState == SignStabilityState.stable,
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () {
                            cameraProvider.toggleStream(_onCameraImage);
                          },
                          icon: Icon(
                            cameraProvider.isStreaming
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: Colors.white,
                            size: 28,
                          ),
                          tooltip: cameraProvider.isStreaming
                              ? 'إيقاف مؤقت'
                              : 'استئناف',
                        ),
                        IconButton(
                          onPressed: cameraProvider.switchCamera,
                          icon: const Icon(
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

  Widget _buildTranslationSection(BuildContext context) {
    return Consumer<GlossController>(
      builder: (context, glossController, _) {
        final hasSign = glossController.hasSign;
        final hasSentence = glossController.hasSentence;
        final isGenerating = glossController.isGenerating;
        final tokens = glossController.bufferedGlossTokens;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // رأس البطاقة مع شارة الحالة
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'ترجمة لغة الإشارة',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    if (isGenerating)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'جارٍ صياغة الجملة...',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber),
                            ),
                          ],
                        ),
                      )
                    else if (glossController.isModelReady)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline, size: 13, color: Colors.green),
                            SizedBox(width: 4),
                            Text(
                              'Gemma3 جاهز',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const Divider(height: 20),

                // 1. Fast Path: الإشارة الفورية المستقرة
                if (hasSign) ...[
                  Row(
                    children: [
                      const Text(
                        'الإشارة الفورية (Fast Path): ',
                        style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          glossController.currentSign!,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],

                // تسلسل الإشارات المسجلة
                if (tokens.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'التسلسل: ',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      ...tokens.map(
                        (t) => Chip(
                          label: Text(t, style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.clear_all, size: 18),
                        tooltip: 'مسح التسلسل',
                        onPressed: glossController.clearAll,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // 2. Sentence Path: الجملة المكتملة المصوغة عبر Gemma3 GGUF
                if (hasSentence) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            glossController.currentSentence!,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              height: 1.4,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.volume_up_rounded),
                          tooltip: 'نطق الجملة',
                          onPressed: () {
                            context.read<SignProvider>().speakText(glossController.currentSentence!);
                          },
                        ),
                      ],
                    ),
                  ),
                ] else if (!hasSign) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        'وجّه يدك نحو الكاميرا لبدء التعرف على الإشارات',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDebugPanelSection(BuildContext context) {
    return Consumer<CameraProvider>(
      builder: (context, cameraProvider, _) {
        final isFrontCamera = cameraProvider.cameraController?.description.lensDirection ==
            CameraLensDirection.front;

        return HandLandmarksDebugPanel(
          landmarks: cameraProvider.latestLandmarks,
          rawHandDetected: cameraProvider.rawHandDetected,
          handDetectorConfidence: cameraProvider.handDetectorConfidence,
          mediaPipePresenceConfidence: cameraProvider.mediaPipePresenceConfidence,
          trackingConfidence: cameraProvider.trackingConfidence,
          frameId: cameraProvider.frameId,
          resultFrameId: cameraProvider.resultFrameId,
          isStaleResult: cameraProvider.isStaleResult,
          geometryValid: cameraProvider.geometryValid,
          isRealHand: cameraProvider.isRealHand,
          rejectionReason: cameraProvider.rejectionReason,
          consecutiveValidFrames: cameraProvider.consecutiveValidFrames,
          fps: cameraProvider.currentFps,
          latencyMs: cameraProvider.lastProcessingTimeMs,
          isFrontCamera: isFrontCamera,
        );
      },
    );
  }
}

class _LoadingWidget extends StatelessWidget {
  const _LoadingWidget();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جارٍ تشغيل الكاميرا ومعالج MediaPipe...'),
          ],
        ),
      ),
    );
  }
}

class _ErrorWidget extends StatelessWidget {
  final String message;

  const _ErrorWidget({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.videocam_off_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  context.read<CameraProvider>().initializeCamera();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
