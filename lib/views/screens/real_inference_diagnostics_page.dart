import 'package:flutter/material.dart';
import 'package:ishara/models/real_inference_result.dart';
import 'package:ishara/providers/vision_detection_provider.dart';
import 'package:ishara/views/screens/ctc_diagnostics_page.dart';
import 'package:provider/provider.dart';

/// RealInferenceDiagnosticsPage
/// صفحة فحص الاستنتاج الحقيقي للنموذج (Real Sequence Inference & A/B Motion Test)
/// تعمل بتزامن مباشر مع الـ Ring Buffer ومجرى الكاميرا المستمر في الخلفية دون أي انقطاع.
class RealInferenceDiagnosticsPage extends StatefulWidget {
  const RealInferenceDiagnosticsPage({super.key});

  @override
  State<RealInferenceDiagnosticsPage> createState() => _RealInferenceDiagnosticsPageState();
}

class _RealInferenceDiagnosticsPageState extends State<RealInferenceDiagnosticsPage> {
  bool _isInferring = false;
  String? _lastError;

  /// تنفيذ الاستنتاج الحقيقي لـ Test A أو Test B
  Future<void> _captureTest(String testLabel) async {
    if (_isInferring) return;

    setState(() {
      _isInferring = true;
      _lastError = null;
    });

    try {
      final provider = context.read<VisionDetectionProvider>();
      final result = await provider.captureRealInference(testLabel: testLabel);

      if (!result.isSuccess && mounted) {
        setState(() {
          _lastError = '[${result.errorCode}] ${result.errorMessage}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الاستنتاج: ${result.errorCode} - ${result.errorMessage}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastError = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ غير متوقع: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInferring = false;
        });
      }
    }
  }

  /// نسخ تقرير الاستنتاج الحقيقي الكامل إلى الحافظة
  Future<void> _copyReport() async {
    final provider = context.read<VisionDetectionProvider>();
    await provider.copyRealInferenceReport();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'تم نسخ تقرير الاستنتاج الحقيقي (Real Inference Report)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Real Sequence Inference Test',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CtcDiagnosticsPage(),
                ),
              );
            },
            icon: const Icon(Icons.code_rounded),
            tooltip: 'CTC Diagnostics',
          ),
          IconButton(
            onPressed: _copyReport,
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'نسخ التقرير',
          ),
        ],
      ),
      body: Consumer<VisionDetectionProvider>(
        builder: (context, visionProvider, _) {
          final state = visionProvider.state;
          final realService = visionProvider.realInferenceService;
          final session = realService.getSession();

          final int bufferCount = state.ringBufferStatus?.frameCount ?? 0;
          final bool isBufferReady = bufferCount >= 128;
          final double qualityScore = state.qualityReport?.rawCoveragePercent ?? 0.0;
          final int newFrames = realService.newFramesSinceTestA;
          final comparison = session.comparison;

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_lastError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _lastError!,
                              style: TextStyle(color: Colors.red.shade900, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── 1. بطاقة REAL MODEL INFERENCE STATUS ──
                  _buildStatusCard(
                    isBufferReady: isBufferReady,
                    bufferCount: bufferCount,
                    qualityScore: qualityScore,
                    isModelReady: visionProvider.isInitialized,
                  ),
                  const SizedBox(height: 16),

                  // ── 2. قسم التقاط ومقارنة الحركات (A / B MOTION TEST) ──
                  _buildCaptureControlsCard(
                    context: context,
                    session: session,
                    isBufferReady: isBufferReady,
                    newFrames: newFrames,
                    visionProvider: visionProvider,
                  ),
                  const SizedBox(height: 16),

                  // ── 3. بطاقة مقارنة الحركة (A vs B COMPARISON) ──
                  if (comparison != null) ...[
                    _buildComparisonCard(comparison),
                    const SizedBox(height: 16),
                  ],

                  // ── 4. أزرار الإجراءات والنسخ ──
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _copyReport,
                          icon: const Icon(Icons.copy_all_rounded, size: 20),
                          label: const Text(
                            'COPY REAL INFERENCE REPORT',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          visionProvider.resetRealInferenceSession();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        label: const Text('RESET'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── 5. عرض التقرير النصي التفاعلي (ASCII Report Viewer) ──
                  _buildReportViewer(realService.generateReport()),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 1. بطاقة الحالة الحية للموديل والـ Buffer وجودة التسلسل
  Widget _buildStatusCard({
    required bool isBufferReady,
    required int bufferCount,
    required double qualityScore,
    required bool isModelReady,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'REAL MODEL INFERENCE',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isBufferReady
                        ? Colors.green.shade700.withValues(alpha: 0.12)
                        : Colors.orange.shade700.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isBufferReady
                          ? Colors.green.shade700.withValues(alpha: 0.3)
                          : Colors.orange.shade700.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    isBufferReady ? 'READY ✅' : 'FILLING BUFFER ($bufferCount/128)',
                    style: TextStyle(
                      color: isBufferReady ? Colors.green.shade700 : Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            _buildDetailRow(
              label: 'Model Interpreter',
              value: isModelReady ? 'READY ✅' : 'NOT READY ⚠️',
              isSuccess: isModelReady,
            ),
            const SizedBox(height: 6),
            _buildDetailRow(
              label: 'Buffer Status',
              value: '$bufferCount/128 ${isBufferReady ? "✅" : "⏳"}',
              isSuccess: isBufferReady,
            ),
            const SizedBox(height: 6),
            _buildDetailRow(
              label: 'Real Input Shape',
              value: '[1, 128, 86, 2] ✅',
              forceLtr: true,
              isSuccess: true,
            ),
            const SizedBox(height: 6),
            _buildDetailRow(
              label: 'Sequence Quality',
              value: '${qualityScore.toStringAsFixed(2)} %',
              forceLtr: true,
              isSuccess: qualityScore > 70,
            ),
          ],
        ),
      ),
    );
  }

  /// 2. عناصر التحكم في التقاط واختبار الحركات A و B
  Widget _buildCaptureControlsCard({
    required BuildContext context,
    required RealInferenceSession session,
    required bool isBufferReady,
    required int newFrames,
    required VisionDetectionProvider visionProvider,
  }) {
    final testA = session.testA;
    final testB = session.testB;
    final bool canCaptureA = isBufferReady && !_isInferring;
    final bool canCaptureB = isBufferReady && testA != null && !_isInferring;
    final bool hasFreshWindow = newFrames >= 128;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Test A Button & Summary ──
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canCaptureA ? () => _captureTest('TEST A') : null,
                    icon: _isInferring && testA == null
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.motion_photos_on_rounded, size: 20),
                    label: const Text(
                      'CAPTURE TEST A',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      backgroundColor: Colors.indigo.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildStatusChip(
                  label: 'Test A',
                  status: testA == null ? 'WAITING' : (testA.isSuccess ? 'PASS' : 'FAIL'),
                  isSuccess: testA?.isSuccess ?? false,
                  isWaiting: testA == null,
                ),
              ],
            ),

            if (testA != null) ...[
              const SizedBox(height: 10),
              _buildInferenceBrief(testA),
            ],

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // ── فاصل النافذة الزمنية المستقلة (Window Separation) ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      hasFreshWindow ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                      size: 18,
                      color: hasFreshWindow ? Colors.green.shade700 : Colors.amber.shade800,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'New Test Frames: $newFrames/128',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: hasFreshWindow ? Colors.green.shade700 : Colors.amber.shade900,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {
                    visionProvider.startNewTestWindow();
                  },
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('START NEW TEST', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (newFrames / 128.0).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(
                  hasFreshWindow ? Colors.green.shade600 : Colors.amber.shade600,
                ),
              ),
            ),
            if (!hasFreshWindow && testA != null) ...[
              const SizedBox(height: 4),
              Text(
                'قم بالحركة الثانية الآن؛ سيتم استبدال إطارات الحركة الأولى تلقائياً ($newFrames/128)',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // ── Test B Button & Summary ──
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canCaptureB ? () => _captureTest('TEST B') : null,
                    icon: _isInferring && testB == null
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.motion_photos_on_rounded, size: 20),
                    label: const Text(
                      'CAPTURE TEST B',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildStatusChip(
                  label: 'Test B',
                  status: testB == null ? 'WAITING' : (testB.isSuccess ? 'PASS' : 'FAIL'),
                  isSuccess: testB?.isSuccess ?? false,
                  isWaiting: testB == null,
                ),
              ],
            ),

            if (testB != null) ...[
              const SizedBox(height: 10),
              _buildInferenceBrief(testB),
            ],
          ],
        ),
      ),
    );
  }

  /// ملخص سريع لنتائج الاستنتاج لكل Test
  Widget _buildInferenceBrief(SingleRealInferenceResult res) {
    if (!res.isSuccess) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Text(
          '❌ [${res.errorCode}] ${res.errorMessage}',
          style: TextStyle(color: Colors.red.shade900, fontSize: 12),
        ),
      );
    }

    final String argmaxPreview = res.rawArgmax.take(10).join(', ');
    final String uniqueStr = res.uniqueClasses.join(', ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Inference Time: ${res.inferenceTimeMs} ms',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  'Output: [${res.outputShape.join(',')}]',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              'Raw Argmax (first 10): [$argmaxPreview...]',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 3),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              'Unique Classes (${res.uniqueClasses.length}): [$uniqueStr]',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 3),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              'Blank Top-1: ${res.blankTop1Count} / 29 | Min: ${res.outputMin.toStringAsFixed(2)} | Max: ${res.outputMax.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  /// 3. بطاقة مقارنة الحركة (A vs B)
  Widget _buildComparisonCard(RealInferenceComparisonResult comp) {
    final bool responds = comp.modelRespondsToRealMotion;
    final bannerColor = responds ? Colors.green.shade800 : Colors.orange.shade800;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'A vs B COMPARISON',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: bannerColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: bannerColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    responds ? 'MOTION DETECTED ✅' : 'IDENTICAL OUTPUT ⚠️',
                    style: TextStyle(
                      color: bannerColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            _buildDetailRow(
              label: 'Argmax Positions Changed',
              value: '${comp.argmaxPositionsChanged} / 29',
              forceLtr: true,
              isSuccess: comp.argmaxPositionsChanged > 0,
            ),
            const SizedBox(height: 6),
            _buildDetailRow(
              label: 'Max Absolute Difference',
              value: comp.maxAbsoluteDifference.toStringAsFixed(4),
              forceLtr: true,
              isSuccess: comp.maxAbsoluteDifference > 0.01,
            ),
            const SizedBox(height: 6),
            _buildDetailRow(
              label: 'Mean Absolute Difference',
              value: comp.meanAbsoluteDifference.toStringAsFixed(4),
              forceLtr: true,
              isSuccess: comp.meanAbsoluteDifference > 0.001,
            ),
            const SizedBox(height: 6),
            _buildDetailRow(
              label: 'Outputs Identical',
              value: comp.outputsIdentical ? 'YES ⚠️' : 'NO ✅',
              isSuccess: !comp.outputsIdentical,
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bannerColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: bannerColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    responds ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                    color: bannerColor,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'MODEL RESPONDS TO REAL MOTION: ${responds ? "YES ✅" : "NO ⚠️"}',
                      style: TextStyle(
                        color: bannerColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 4. شريحة حالة صغيرة (Chip)
  Widget _buildStatusChip({
    required String label,
    required String status,
    required bool isSuccess,
    required bool isWaiting,
  }) {
    final Color color = isWaiting
        ? Colors.grey.shade600
        : (isSuccess ? Colors.green.shade700 : Colors.red.shade700);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label: $status',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  /// سطر تفصيلي مع دعم LTR الصارم
  Widget _buildDetailRow({
    required String label,
    required String value,
    bool forceLtr = false,
    bool? isSuccess,
  }) {
    Color? valColor;
    if (isSuccess != null) {
      valColor = isSuccess ? Colors.green.shade700 : Colors.orange.shade800;
    }

    final valueWidget = Text(
      value,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 13,
        color: valColor,
        fontFamily: forceLtr ? 'monospace' : null,
      ),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        if (forceLtr)
          Directionality(
            textDirection: TextDirection.ltr,
            child: valueWidget,
          )
        else
          valueWidget,
      ],
    );
  }

  /// 5. عارض التقرير النصي التفاعلي بالخط الثابت
  Widget _buildReportViewer(String reportText) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF313244)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.terminal_rounded, color: Color(0xFF89B4FA), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'REPORT PREVIEW',
                    style: TextStyle(
                      color: Color(0xFFCDD6F4),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: _copyReport,
                icon: const Icon(Icons.copy_rounded, color: Color(0xFF89B4FA), size: 18),
                tooltip: 'نسخ التقرير',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF313244), height: 1),
          const SizedBox(height: 12),
          Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(
              reportText,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: Color(0xFFA6ADC8),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
