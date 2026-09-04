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
  bool _developerDebugMode = false;

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
        title: GestureDetector(
          onLongPress: () {
            setState(() {
              _developerDebugMode = !_developerDebugMode;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _developerDebugMode
                      ? 'تم تفعيل أدوات المطور (Debug Mode)'
                      : 'تم إخفاء أدوات المطور',
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          child: Row(
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
          const SizedBox(height: 14),
          _buildTranslationSection(context),
          if (_developerDebugMode) ...[
            const SizedBox(height: 12),
            _buildDebugPanelSection(context),
          ],
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
                  const SizedBox(height: 14),
                  _buildTranslationSection(context),
                ],
              ),
            ),
          ),
          if (_developerDebugMode) ...[
            const SizedBox(width: 24),
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                child: _buildDebugPanelSection(context),
              ),
            ),
          ],
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
                  landmarks: cameraProvider.isRealHand
                      ? cameraProvider.latestLandmarks
                      : null,
                  showLandmarks: _developerDebugMode,
                  isHandDetected: cameraProvider.isRealHand,
                  isStreaming: cameraProvider.isStreaming,
                  activeSignLabel: glossController.currentSign,
                  isStable:
                      glossController.stabilityState ==
                      SignStabilityState.stable,
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

  Widget _buildTranslationSection(BuildContext context) {
    return Consumer2<GlossController, CameraProvider>(
      builder: (context, glossController, cameraProvider, _) {
        final displayText = glossController.displayText;
        final hasContent = glossController.hasContent;
        final hasSentence = glossController.hasSentence;
        final hasBuffer = glossController.hasBuffer;
        final isGenerating = glossController.isGenerating;
        final isHandDetected = cameraProvider.isRealHand;
        final stateColor = _getStateColor(context, glossController.stabilityState);

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // رأس البطاقة مع شارة الحالة
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.auto_awesome,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'ترجمة لغة الإشارة',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // شارة آلة الحالة الزمنية (State Machine Badge)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: stateColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: stateColor.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            glossController.stabilityState.arabicLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: stateColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isGenerating)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.amber),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.amber,
                              ),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'جارٍ صياغة الجملة...',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const Divider(height: 24),

                // ── عرض الترجمة النظيفة وتجميع الـ Gloss الحي ──
                if (hasContent) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: hasSentence
                            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                            : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              hasSentence ? 'الجملة المصاغة (Gemma3 GGUF):' : 'تجميع الإشارات الحية (Gloss Buffer):',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: hasSentence
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey.shade600,
                              ),
                            ),
                            if (hasBuffer && !hasSentence)
                              Text(
                                '${glossController.bufferedGlossTokens.length} كلمات',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          displayText!,
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            fontSize: hasSentence ? 24 : 21,
                            fontWeight: FontWeight.bold,
                            height: 1.5,
                            letterSpacing: 0.2,
                            color: hasSentence ? null : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // زر ترجم الآن اليدوي (Manual Translation Trigger)
                      if (hasBuffer && !isGenerating) ...[
                        FilledButton.icon(
                          onPressed: () {
                            glossController.triggerManualTranslation();
                          },
                          icon: const Icon(Icons.translate_rounded, size: 18),
                          label: const Text('ترجم الآن'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      FilledButton.tonalIcon(
                        onPressed: () {
                          context.read<SignProvider>().speakText(displayText);
                        },
                        icon: const Icon(Icons.volume_up_rounded, size: 20),
                        label: const Text('نطق'),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: () {
                          glossController.clearAll();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        tooltip: 'مسح',
                      ),
                    ],
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isHandDetected) ...[
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Text(
                            'جارٍ التعرف...',
                            style: TextStyle(
                              fontSize: 17,
                              color: isHandDetected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: const Text(
          'أدوات المطور والفحص الفني (MediaPipe)',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        leading: const Icon(Icons.tune_rounded, size: 20, color: Colors.grey),
        children: [
          Consumer<CameraProvider>(
            builder: (context, cameraProvider, _) {
              final isFrontCamera =
                  cameraProvider.cameraController?.description.lensDirection ==
                  CameraLensDirection.front;

              return HandLandmarksDebugPanel(
                landmarks: cameraProvider.latestLandmarks,
                rawHandDetected: cameraProvider.rawHandDetected,
                handDetectorConfidence: cameraProvider.handDetectorConfidence,
                mediaPipePresenceConfidence:
                    cameraProvider.mediaPipePresenceConfidence,
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
          ),
        ],
      ),
    );
  }

  Color _getStateColor(BuildContext context, SignStabilityState state) {
    switch (state) {
      case SignStabilityState.idle:
      case SignStabilityState.detecting:
        return Colors.grey;
      case SignStabilityState.signing:
      case SignStabilityState.candidate:
        return Colors.blue;
      case SignStabilityState.candidateStable:
        return Colors.orange;
      case SignStabilityState.committed:
      case SignStabilityState.stable:
        return Colors.green;
      case SignStabilityState.cooldown:
        return Colors.purple;
    }
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
