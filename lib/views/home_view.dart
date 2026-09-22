import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/controllers/camera_controller.dart';
import 'package:ishara/controllers/ishara_test_controller.dart';
import 'package:ishara/models/ishara_recognition_test_session.dart';
import 'package:ishara/providers/vision_detection_provider.dart';
import 'package:ishara/services/ishara_native_vision_service.dart';
import 'package:ishara/views/screens/ctc_diagnostics_page.dart';
import 'package:ishara/views/screens/sign_recognition_diagnostics_page.dart';
import 'package:ishara/views/widgets/camera_preview_widget.dart';
import 'package:ishara/views/widgets/native_camera_preview_widget.dart';
import 'package:provider/provider.dart';

/// HomeView
/// الشاشة الرئيسية لتطبيق Ishara:
/// تدعم افتراضياً Native Android Vision Engine عالي الأداء مع استيفاء زمني ذكي وتتبع الحركة بالنسبة للجسم،
/// مع إمكانية التبديل إلى Legacy Flutter Vision للمقارنة والقياس دون كسر التطبيق.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  /// الوضع الافتراضي: Native Android Kotlin Engine عالي الأداء
  bool useNativeVision = true;

  /// علم إظهار تفاصيل المطورين (محجوبة عن المستخدم العادي افتراضياً)
  final bool showDeveloperDebug = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initVisionMode();
    });
  }

  void _initVisionMode() {
    if (useNativeVision) {
      final nativeVision = context.read<IsharaNativeVisionService>();
      if (!nativeVision.isCameraRunning) {
        nativeVision.startVision(useFrontCamera: true);
      }
    } else {
      final cameraProvider = context.read<CameraProvider>();
      cameraProvider.initializeCamera().then((_) {
        if (mounted && cameraProvider.isReady) {
          cameraProvider.startStream(_onLegacyCameraImage);
        }
      });
    }
  }

  /// معالجة كل إطار كاميرا في الوضع القديم (Legacy Fallback)
  Future<void> _onLegacyCameraImage(CameraImage image) async {
    if (!mounted || useNativeVision) return;
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
        debugPrint('[HomeView] ⚠️ Error in _onLegacyCameraImage: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppConstants.appName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
        actions: [
          // زر تبديل الكاميرا (Front <-> Back)
          IconButton(
            onPressed: () {
              if (useNativeVision) {
                context.read<IsharaNativeVisionService>().switchCamera();
              } else {
                context.read<CameraProvider>().switchCamera();
              }
            },
            icon: const Icon(Icons.flip_camera_ios_rounded),
            tooltip: 'تبديل الكاميرا',
          ),
          // قائمة أدوات المطور والتبديل بين Native و Legacy
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'أدوات المطور',
            onSelected: (value) {
              if (value == 'toggle_engine') {
                setState(() {
                  useNativeVision = !useNativeVision;
                  _initVisionMode();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      useNativeVision
                          ? 'تم التحويل إلى: Native Android Vision (60 FPS)'
                          : 'تم التحويل إلى: Legacy Flutter Vision',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              } else if (value == 'sign_recognition') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SignRecognitionDiagnosticsPage(),
                  ),
                );
              } else if (value == 'ctc_diagnostics') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CtcDiagnosticsPage(),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle_engine',
                child: Row(
                  children: [
                    Icon(
                      useNativeVision
                          ? Icons.speed_rounded
                          : Icons.history_rounded,
                      size: 20,
                      color: useNativeVision ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      useNativeVision
                          ? 'الوضع الحالي: Native Kotlin ⚡'
                          : 'الوضع الحالي: Legacy Flutter',
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'sign_recognition',
                child: Row(
                  children: [
                    Icon(Icons.motion_photos_auto_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('Sign Recognition Diagnostics'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'ctc_diagnostics',
                child: Row(
                  children: [
                    Icon(Icons.analytics_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('CTC & Vocab Diagnostics'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: useNativeVision
            ? _buildNativeVisionBody(context)
            : _buildLegacyVisionBody(context),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // ── 1. واجهة Native Android Vision Engine عالي الأداء ──
  // ════════════════════════════════════════════════════════════════

  Widget _buildNativeVisionBody(BuildContext context) {
    return Consumer<IsharaNativeVisionService>(
      builder: (context, nativeVision, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. الكاميرا الأصلية النظيفة (Hardware Accelerated PreviewView)
              Container(
                constraints: const BoxConstraints(maxHeight: 460),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: const NativeCameraPreviewWidget(),
              ),
              const SizedBox(height: 18),

              // 2. واجهة التفاعل اللحظية المبسطة
              _buildNativeInteractionSection(context, nativeVision),

              // 3. تشخيصات المطورين (محجوبة عن المستخدم العادي)
              if (showDeveloperDebug) ...[
                const SizedBox(height: 24),
                _buildNativeDebugCard(nativeVision),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildNativeInteractionSection(
    BuildContext context,
    IsharaNativeVisionService nativeVision,
  ) {
    final state = nativeVision.state;

    switch (state) {
      case NativeSignState.idle:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'الحالة: جاهز',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Text(
                'أدِّ الإشارة بالسرعة الطبيعية أمام الكاميرا',
                style: TextStyle(fontSize: 14, color: Colors.blueGrey),
              ),
            ],
          ),
        );

      case NativeSignState.starting:
      case NativeSignState.signing:
      case NativeSignState.ending:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    state.localizedTitle,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  backgroundColor: Colors.grey.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        );

      case NativeSignState.processing:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.indigo.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.indigo.withValues(alpha: 0.25)),
          ),
          child: const Column(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
                ),
              ),
              SizedBox(height: 14),
              Text(
                'جاري التحليل...',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
            ],
          ),
        );

      case NativeSignState.result:
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.green.shade400, width: 1.5),
          ),
          child: Column(
            children: [
              const Text(
                'النتيجة:',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                nativeVision.displayResult,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  // زر نسخ النتيجة (ينسخ تقرير Section 35 الكامل للحافظة)
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await nativeVision.copyDiagnosticReport();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Row(
                                children: [
                                  Icon(Icons.check_circle_rounded,
                                      color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'تم نسخ التقرير الكامل ✓',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
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
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      label: const Text(
                        'نسخ النتيجة',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // زر إشارة جديدة
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: () => nativeVision.resetSession(),
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text(
                        'إشارة جديدة',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blueGrey.shade800,
                        side: BorderSide(color: Colors.grey.shade400),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      case NativeSignState.failed:
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 36, color: Colors.red.shade700),
              const SizedBox(height: 10),
              Text(
                nativeVision.displayResult,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => nativeVision.resetSession(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text(
                    'إعادة المحاولة',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildNativeDebugCard(IsharaNativeVisionService nativeVision) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Native Vision Diagnostics',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            'Original Duration: ${nativeVision.lastDurationMs} ms | '
            'Original Frames: ${nativeVision.lastOriginalFrames} | '
            'Inference: ${nativeVision.lastInferenceMs} ms',
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
          Text(
            'Decoded IDs: ${nativeVision.lastDecodedIds}',
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // ── 2. واجهة Legacy Flutter Vision (Fallback) ──
  // ════════════════════════════════════════════════════════════════

  Widget _buildLegacyVisionBody(BuildContext context) {
    return Consumer2<CameraProvider, IsharaTestController>(
      builder: (context, cameraProvider, testController, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                constraints: const BoxConstraints(maxHeight: 460),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: CameraPreviewWidget(
                  cameraController: cameraProvider.cameraController,
                  showOverlay: false,
                  showNumbers: false,
                  isStreaming: cameraProvider.isStreaming,
                ),
              ),
              const SizedBox(height: 18),
              _buildLegacyInterface(context, testController),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLegacyInterface(
      BuildContext context, IsharaTestController testController) {
    final state = testController.state;
    if (state == RecognitionTestState.idle) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: testController.canStartTest
              ? () => testController.startSimpleTest()
              : null,
          icon: const Icon(Icons.play_arrow_rounded, size: 28),
          label: const Text(
            'ابدأ الاختبار (Legacy)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else if (state == RecognitionTestState.collecting) {
      return Column(
        children: [
          const Text('جاري الالتقاط (Legacy)...'),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: testController.progressFraction),
          Text('${testController.collectedFrames} / 128'),
        ],
      );
    } else if (state == RecognitionTestState.processing) {
      return const Center(child: Text('جاري التحليل...'));
    } else {
      return Column(
        children: [
          Text(testController.displayResult,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => testController.copyResult(),
                  child: const Text('نسخ النتيجة'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => testController.resetTest(),
                  child: const Text('اختبار جديد'),
                ),
              ),
            ],
          ),
        ],
      );
    }
  }
}
