import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/controllers/camera_controller.dart';
import 'package:ishara/controllers/ishara_test_controller.dart';
import 'package:ishara/models/ishara_test_state.dart';
import 'package:ishara/providers/vision_detection_provider.dart';
import 'package:ishara/views/widgets/camera_preview_widget.dart';
import 'package:provider/provider.dart';

// ── Debug UI & Diagnostic Screens (kept preserved for future debugging) ──
// import 'package:ishara/views/widgets/body_parts_status_card.dart';
// import 'package:ishara/views/screens/real_inference_diagnostics_page.dart';
// import 'package:ishara/views/screens/model_diagnostics_page.dart';

/// HomeView
/// الشاشة الرئيسية المبسطة والآلية لاختبار إشارات Ishara:
/// 1. Camera Preview كبيرة ونظيفة بدون أي نصوص أو Debug Overlay.
/// 2. زرين جنب بعضهما: [ TEST A ] و [ TEST B ].
/// 3. عد تنازلي (3.. 2.. 1) ثم تسجيل 128 إطاراً مع Progress Bar.
/// 4. زر واحد واضح: [ COPY RESULT ] يظهر عند اكتمال الاختبارين مع توست "Result copied ✓".
/// 5. زر [ RESET ] لتصفير الاختبار مع بقاء الكاميرا تعمل.
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

  /// معالجة كل إطار كاميرا وتحديث الـ Ring Buffer والـ Test Controller
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

      if (!mounted) return;
      final latestId =
          visionProvider.state.ringBufferStatus?.latestFrameSequenceId;
      if (latestId != null) {
        context.read<IsharaTestController>().onFrameProcessed(latestId);
      }
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
        title: Text(
          AppConstants.appName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 1. CAMERA PREVIEW (كبيرة ونظيفة بدون أي نصوص أو أوفرلاي) ──
                  _buildCameraSection(cameraProvider, testController),
                  const SizedBox(height: 18),

                  // ── 2. [ TEST A ]     [ TEST B ] جنب بعضهما ──
                  _buildTestButtons(testController),

                  // ── 3. FRAMES COUNTER + PROGRESS BAR (أثناء التسجيل فقط) ──
                  if (testController.isRecording) ...[
                    const SizedBox(height: 18),
                    _buildRecordingProgress(testController),
                  ],

                  // ── مؤشر المعالجة اللحظية عند اكتمال الـ 128 إطاراً ──
                  if (testController.state.isProcessing) ...[
                    const SizedBox(height: 18),
                    _buildProcessingIndicator(testController),
                  ],

                  // ── 4. [ COPY RESULT ] (يظهر فقط بعد اكتمال Test A و Test B) ──
                  if (testController.isCompleted) ...[
                    const SizedBox(height: 22),
                    _buildCopyResultButton(context, testController),
                  ],

                  // ── 5. [ RESET ] ──
                  const SizedBox(height: 14),
                  _buildResetButton(testController),

                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 1. قسم الكاميرا النظيفة مع العد التنازلي الشفاف (3.. 2.. 1)
  Widget _buildCameraSection(
    CameraProvider cameraProvider,
    IsharaTestController testController,
  ) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 440),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // الكاميرا بدون أي Overlay نصوص أو معالم
          CameraPreviewWidget(
            cameraController: cameraProvider.cameraController,
            showOverlay: false,
            showNumbers: false,
            isStreaming: cameraProvider.isStreaming,
          ),

          // عد تنازلي (3.. 2.. 1) أنيق وواضح فوق الكاميرا عند بدء الاختبار
          if (testController.isCountdown)
            Container(
              color: Colors.black.withValues(alpha: 0.35),
              child: Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.70),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${testController.countdown}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 52,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 2. زري [ TEST A ] و [ TEST B ] جنب بعضهما
  Widget _buildTestButtons(IsharaTestController testController) {
    final bool isTestADone = testController.isTestADone;
    final bool isTestBDone = testController.isTestBDone;

    // أثناء Test A: Test B disabled | أثناء Test B: Test A disabled
    final bool canA = testController.canStartTestA;
    final bool canB = testController.canStartTestB;

    return Row(
      children: [
        // ── TEST A ──
        Expanded(
          child: ElevatedButton.icon(
            onPressed: canA ? () => testController.startTestA() : null,
            icon: Icon(
              isTestADone
                  ? Icons.check_circle_rounded
                  : Icons.play_arrow_rounded,
              size: 22,
            ),
            label: Text(
              isTestADone ? 'TEST A ✓' : 'TEST A',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: isTestADone
                  ? Colors.green.shade700
                  : Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: isTestADone
                  ? Colors.green.shade700.withValues(alpha: 0.85)
                  : Colors.grey.shade300,
              disabledForegroundColor:
                  isTestADone ? Colors.white : Colors.grey.shade600,
              elevation: canA ? 2 : 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),

        // ── TEST B ──
        Expanded(
          child: ElevatedButton.icon(
            onPressed: canB ? () => testController.startTestB() : null,
            icon: Icon(
              isTestBDone
                  ? Icons.check_circle_rounded
                  : Icons.play_arrow_rounded,
              size: 22,
            ),
            label: Text(
              isTestBDone ? 'TEST B ✓' : 'TEST B',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: isTestBDone
                  ? Colors.green.shade700
                  : Theme.of(context).colorScheme.secondary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: isTestBDone
                  ? Colors.green.shade700.withValues(alpha: 0.85)
                  : Colors.grey.shade300,
              disabledForegroundColor:
                  isTestBDone ? Colors.white : Colors.grey.shade600,
              elevation: canB ? 2 : 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 3. عداد الإطارات والـ Progress Bar (أثناء التسجيل فقط)
  Widget _buildRecordingProgress(IsharaTestController testController) {
    final int frames = testController.recordedFrames;
    final double progress = (frames / 128.0).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                testController.activeTestLabel,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  'Frames: $frames / 128',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.grey.withValues(alpha: 0.25),
              valueColor: AlwaysStoppedAnimation<Color>(
                testController.state == IsharaTestState.recordingA
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// مؤشر المعالجة اللحظية للاستنتاج
  Widget _buildProcessingIndicator(IsharaTestController testController) {
    return const Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          SizedBox(width: 10),
          Text(
            'جارٍ معالجة الحركة...',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }

  /// 4. زر نسخ التقرير النهائي (يظهر فقط بعد اكتمال Test A و Test B)
  Widget _buildCopyResultButton(
    BuildContext context,
    IsharaTestController testController,
  ) {
    return ElevatedButton.icon(
      onPressed: () async {
        await testController.copyResult();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Result copied ✓',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade800,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      icon: const Icon(Icons.copy_all_rounded, size: 22),
      label: const Text(
        'COPY RESULT',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 3,
      ),
    );
  }

  /// 5. زر [ RESET ] لتصفير الاختبار
  Widget _buildResetButton(IsharaTestController testController) {
    return Center(
      child: TextButton.icon(
        onPressed: () {
          testController.reset();
        },
        icon: const Icon(Icons.restart_alt_rounded, size: 18),
        label: const Text(
          'RESET',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        style: TextButton.styleFrom(
          foregroundColor: Colors.grey.shade700,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
    );
  }
}
