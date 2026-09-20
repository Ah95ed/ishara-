import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/controllers/camera_controller.dart';
import 'package:ishara/controllers/ishara_test_controller.dart';
import 'package:ishara/models/ishara_recognition_test_session.dart';
import 'package:ishara/providers/vision_detection_provider.dart';
import 'package:ishara/views/screens/ctc_diagnostics_page.dart';
import 'package:ishara/views/screens/sign_recognition_diagnostics_page.dart';
import 'package:ishara/views/widgets/camera_preview_widget.dart';
import 'package:provider/provider.dart';

/// HomeView
/// الشاشة الرئيسية المبسطة لاختبار التعرف على لغة الإشارة Ishara:
/// 1. Camera Preview واضحة وكبيرة بدون أي تشويش.
/// 2. [ ابدأ الاختبار ] لبدء جلسة 128 إطاراً من لحظة الضغط.
/// 3. شريط تقدم بسيط أثناء الالتقاط (0..128).
/// 4. شاشة "جاري التحليل..." أثناء تشغيل الاستنتاج مرة واحدة.
/// 5. عرض الكلمات المستخرجة فقط [ بنت - اخ - صغير ] مع زر [ نسخ النتيجة ] وزر [ اختبار جديد ].
/// 6. التشخيصات التفصيلية محفوظة داخلياً ومحجوبة خلف showDeveloperDebug = false.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  /// علم إظهار تفاصيل المطورين (محجوبة عن المستخدم العادي افتراضياً)
  final bool showDeveloperDebug = false;

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
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
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
          // قائمة المطور التشخيصية (متاحة كخيار متقدم فقط)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'أدوات المطور',
            onSelected: (value) {
              if (value == 'sign_recognition') {
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
        child: Consumer2<CameraProvider, IsharaTestController>(
          builder: (context, cameraProvider, testController, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 1. CAMERA PREVIEW (كبيرة ونظيفة بدون أي أوفرلاي مشوش) ──
                  _buildCameraSection(cameraProvider),
                  const SizedBox(height: 18),

                  // ── 2. واجهة الاختبار البسيطة للمستخدم ──
                  _buildSimpleTestInterface(context, testController),

                  // ── 3. تشخيصات المطورين (محجوبة عن المستخدم العادي) ──
                  if (showDeveloperDebug) ...[
                    const SizedBox(height: 24),
                    _buildDeveloperDebugSection(context, testController),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 1. قسم الكاميرا النظيفة
  Widget _buildCameraSection(CameraProvider cameraProvider) {
    return Container(
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
      child: CameraPreviewWidget(
        cameraController: cameraProvider.cameraController,
        showOverlay: false,
        showNumbers: false,
        isStreaming: cameraProvider.isStreaming,
      ),
    );
  }

  /// 2. واجهة الاختبار البسيطة وفق المتطلبات المحددة بدقة
  Widget _buildSimpleTestInterface(
    BuildContext context,
    IsharaTestController testController,
  ) {
    final state = testController.state;

    switch (state) {
      case RecognitionTestState.idle:
        return _buildIdleSection(testController);

      case RecognitionTestState.collecting:
        return _buildCollectingSection(testController);

      case RecognitionTestState.processing:
        return _buildProcessingSection();

      case RecognitionTestState.result:
        return _buildResultSection(context, testController);

      case RecognitionTestState.failed:
        return _buildFailedSection(testController);
    }
  }

  /// حالة IDLE:
  /// الحالة: جاهز
  /// [ ابدأ الاختبار ]
  Widget _buildIdleSection(IsharaTestController testController) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
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
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'الحالة: جاهز',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: testController.canStartTest
                  ? () => testController.startSimpleTest()
                  : null,
              icon: const Icon(Icons.play_arrow_rounded, size: 28),
              label: const Text(
                'ابدأ الاختبار',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// حالة COLLECTING:
  /// جاري الالتقاط...
  /// ProgressIndicator
  /// 84 / 128
  Widget _buildCollectingSection(IsharaTestController testController) {
    final frames = testController.collectedFrames;
    final total = testController.targetFrames;
    final progress = testController.progressFraction;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              SizedBox(width: 10),
              Text(
                'جاري الالتقاط...',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '$frames / $total',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// حالة PROCESSING:
  /// جاري التحليل...
  Widget _buildProcessingSection() {
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
  }

  /// حالة RESULT:
  /// النتيجة:
  /// بنت - اخ - صغير
  /// [ نسخ النتيجة ]
  /// [ اختبار جديد ]
  Widget _buildResultSection(
    BuildContext context,
    IsharaTestController testController,
  ) {
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
            testController.displayResult,
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
              // زر نسخ النتيجة (ينسخ التقرير التشخيصي الكامل إلى الحافظة)
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await testController.copyResult();
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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              // زر اختبار جديد
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: () => testController.resetTest(),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text(
                    'اختبار جديد',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
  }

  /// حالة FAILED:
  /// "لم تكتمل البيانات، أعد المحاولة" أو "الإشارة غير واضحة"
  Widget _buildFailedSection(IsharaTestController testController) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.warning_amber_rounded, size: 36, color: Colors.red.shade700),
          const SizedBox(height: 10),
          Text(
            testController.displayResult,
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
              onPressed: () => testController.resetTest(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(
                'اختبار جديد',
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

  /// 3. شاشة تفاصيل المطورين (محفوظة برمجياً ولا تظهر إلا إذا كانت showDeveloperDebug = true)
  Widget _buildDeveloperDebugSection(
    BuildContext context,
    IsharaTestController testController,
  ) {
    final session = testController.session;
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
            'Developer Diagnostics (Internal Only)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            'Quality: ${session?.sequenceQualityPct.toStringAsFixed(2) ?? "N/A"}% | '
            'RH: ${session?.rhCoveragePct.toStringAsFixed(2) ?? "N/A"}% | '
            'LH: ${session?.lhCoveragePct.toStringAsFixed(2) ?? "N/A"}%',
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
          Text(
            'CTC IDs: ${session?.ctcIds ?? []}',
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
