import 'package:flutter/material.dart';
import 'package:ishara/ml/activity/ishara_sign_activity_detector.dart';
import 'package:ishara/providers/vision_detection_provider.dart';
import 'package:ishara/services/ishara_continuous_sign_service.dart';
import 'package:provider/provider.dart';

/// SignRecognitionDiagnosticsPage
/// صفحة تشخيصية واختبارية شاملة لتمييز الإشارات المستمرة (Continuous Sign Recognition Test):
/// - زر: [ START TEST ] / [ STOP TEST ]
/// - عرض حالة النشاط والحركة (IDLE / SIGNING / ENDING / READY) مع الـ Baseline
/// - عرض جودة الـ Sequence ونسبة التعويض
/// - عرض نوافذ الاستنتاج الثلاثة (Window 1, 2, 3) والتصويت (2/3)
/// - عرض الكلمات المعتمدة النهائية (Accepted Glosses) بـ SelectableText
/// - زر: [ COPY RECOGNITION REPORT ] ينسخ التقرير المطابق لمواصفات البند 28
class SignRecognitionDiagnosticsPage extends StatefulWidget {
  const SignRecognitionDiagnosticsPage({super.key});

  @override
  State<SignRecognitionDiagnosticsPage> createState() =>
      _SignRecognitionDiagnosticsPageState();
}

class _SignRecognitionDiagnosticsPageState
    extends State<SignRecognitionDiagnosticsPage> {
  /// نسخ التقرير الكامل إلى الحافظة
  Future<void> _copyReport(IsharaContinuousSignService service) async {
    await service.copyReportToClipboard();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'تم نسخ تقرير تمييز الإشارات (Report copied ✓)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sign Recognition Test',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Consumer<VisionDetectionProvider>(
        builder: (context, visionProvider, _) {
          final service = visionProvider.continuousSignService;
          return ListenableBuilder(
            listenable: service,
            builder: (context, _) {
              final reportData = service.generateReportData();
              final activity = service.latestActivity;
              final eval = service.latestEvaluation;
              final candidates = service.stabilityTracker.windowHistory;

              return SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── 1. زر التحكم الرئيسي [ START TEST ] / [ STOP TEST ] ──
                      ElevatedButton.icon(
                        onPressed: () {
                          if (service.isTestActive) {
                            service.stopTest();
                          } else {
                            service.startTest();
                          }
                        },
                        icon: Icon(
                          service.isTestActive
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                          size: 24,
                        ),
                        label: Text(
                          service.isTestActive ? 'STOP TEST' : 'START TEST',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 0.5,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: service.isTestActive
                              ? Colors.red.shade700
                              : Colors.indigo.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 3,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── 2. بطاقة حالة النشاط الحركي (Sign Activity Card) ──
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'SIGN ACTIVITY DETECTOR',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  _buildStateBadge(
                                    activity?.state ?? SignActivityState.idle,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 12),

                              _buildMetricRow(
                                label: 'Motion Score',
                                value: (activity?.currentMotion ?? 0.0)
                                    .toStringAsFixed(4),
                                forceLtr: true,
                              ),
                              const SizedBox(height: 8),
                              _buildMetricRow(
                                label: 'Motion Baseline',
                                value: (activity?.baselineMean ?? 0.0)
                                    .toStringAsFixed(4),
                                forceLtr: true,
                              ),
                              const SizedBox(height: 8),
                              _buildMetricRow(
                                label: 'Start Threshold',
                                value: (activity?.startThreshold ?? 0.0)
                                    .toStringAsFixed(4),
                                forceLtr: true,
                              ),
                              const SizedBox(height: 8),
                              _buildMetricRow(
                                label: 'Peak Motion',
                                value: service.activityDetector.peakMotion
                                    .toStringAsFixed(4),
                                forceLtr: true,
                              ),
                              const SizedBox(height: 8),
                              _buildMetricRow(
                                label: 'Sign Duration',
                                value:
                                    '${service.activityDetector.signDurationMs} ms',
                                forceLtr: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── 3. بطاقة جودة التسلسل (Sequence Quality Gate) ──
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'SEQUENCE QUALITY GATE',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 12),

                              _buildMetricRow(
                                label: 'Buffer Capacity',
                                value: '${reportData.bufferCount}/128',
                                forceLtr: true,
                              ),
                              const SizedBox(height: 8),
                              _buildMetricRow(
                                label: 'Quality',
                                value:
                                    '${reportData.qualityPct.toStringAsFixed(2)} %',
                                isPass: reportData.qualityPct >= 85.0,
                                forceLtr: true,
                              ),
                              const SizedBox(height: 8),
                              _buildMetricRow(
                                label: 'Imputation',
                                value:
                                    '${reportData.imputationPct.toStringAsFixed(2)} %',
                                isPass: reportData.imputationPct <= 15.0,
                                forceLtr: true,
                              ),
                              const SizedBox(height: 8),
                              _buildMetricRow(
                                label: 'RH Coverage',
                                value:
                                    '${reportData.rhCoveragePct.toStringAsFixed(2)} %',
                                forceLtr: true,
                              ),
                              const SizedBox(height: 8),
                              _buildMetricRow(
                                label: 'LH Coverage',
                                value:
                                    '${reportData.lhCoveragePct.toStringAsFixed(2)} %',
                                forceLtr: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── 4. بطاقة الاستنتاج الانزلاقي والاستقرار (Sliding & Stability 2/3) ──
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'SLIDING INFERENCE & STABILITY',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  Text(
                                    'Executed: ${service.inferenceExecuted}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 12),

                              _buildMetricRow(
                                label: 'Sliding Stride',
                                value: '${service.slidingStrideFrames} frames',
                                forceLtr: true,
                              ),
                              const SizedBox(height: 8),
                              _buildMetricRow(
                                label: 'Skipped (Busy)',
                                value: '${service.inferenceSkippedBusy}',
                                forceLtr: true,
                              ),
                              const SizedBox(height: 8),
                              _buildMetricRow(
                                label: 'Avg Inference Time',
                                value:
                                    '${service.averageInferenceTimeMs.toStringAsFixed(1)} ms',
                                forceLtr: true,
                              ),
                              const SizedBox(height: 14),

                              const Text(
                                'Last 3 Windows (Candidates):',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),

                              if (candidates.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                  child: Text(
                                    'No candidates recorded yet. Start gesturing to trigger inference.',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              else
                                for (int i = 0; i < candidates.length; i++) ...[
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          'W${i + 1}: ',
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            'IDs: [${candidates[i].decodedIds.join(',')}] → ${candidates[i].glosses.join(', ')}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.indigo,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          '${(candidates[i].sequenceConfidence * 100).toStringAsFixed(1)}%',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.blueGrey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                              const SizedBox(height: 10),
                              const Divider(height: 1),
                              const SizedBox(height: 10),

                              _buildMetricRow(
                                label: 'Stability Voting',
                                value:
                                    '[${reportData.stableIds.join(',')}] = ${reportData.votes} / 3',
                                isPass: reportData.stabilityPass,
                                forceLtr: true,
                              ),
                              const SizedBox(height: 8),
                              _buildMetricRow(
                                label: 'Evaluation Reason',
                                value: eval?.reasonCode ?? 'WAITING_ACTIVITY',
                                forceLtr: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── 5. بطاقة النتيجة النهائية المعتمدة (Accepted Glosses) ──
                      Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: reportData.isAccepted
                                ? Colors.green.shade600
                                : Colors.indigo.shade300,
                            width: 1.5,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        reportData.isAccepted
                                            ? Icons.check_circle_rounded
                                            : Icons.translate_rounded,
                                        color: reportData.isAccepted
                                            ? Colors.green.shade700
                                            : Colors.indigo,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'ACCEPTED GLOSSES',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: reportData.isAccepted
                                          ? Colors.green.shade50
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: reportData.isAccepted
                                            ? Colors.green.shade300
                                            : Colors.grey.shade400,
                                      ),
                                    ),
                                    child: Text(
                                      reportData.isAccepted
                                          ? 'ACCEPTED ✅'
                                          : 'SEARCHING ⏳',
                                      style: TextStyle(
                                        color: reportData.isAccepted
                                            ? Colors.green.shade800
                                            : Colors.blueGrey,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 12),

                              if (service.acceptedGlosses.isEmpty) ...[
                                const Center(
                                  child: Padding(
                                    padding:
                                        EdgeInsets.symmetric(vertical: 16.0),
                                    child: Text(
                                      'لا توجد إشارة معتمدة بعد.\nقم بأداء حركة واضحة أمام الكاميرا وانتظر استقرارها.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ] else ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.green.shade200,
                                    ),
                                  ),
                                  child: SelectableText(
                                    '[${service.acceptedGlosses.join(', ')}]',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── 6. زر [ COPY RECOGNITION REPORT ] ──
                      OutlinedButton.icon(
                        onPressed: () => _copyReport(service),
                        icon: const Icon(Icons.copy_all_rounded, size: 20),
                        label: const Text(
                          'COPY RECOGNITION REPORT',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          foregroundColor: Colors.indigo.shade800,
                          side: BorderSide(
                            color: Colors.indigo.shade700,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── 7. عارض التقرير الكامل (Monospace ASCII Preview) ──
                      _buildReportViewer(reportData.toReportText(), service),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStateBadge(SignActivityState state) {
    Color bg;
    Color fg;
    String text = state.nameUpper;

    switch (state) {
      case SignActivityState.idle:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        break;
      case SignActivityState.signing:
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        break;
      case SignActivityState.ending:
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade900;
        break;
      case SignActivityState.ready:
        bg = Colors.green.shade100;
        fg = Colors.green.shade900;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  Widget _buildMetricRow({
    required String label,
    required String value,
    bool? isPass,
    bool forceLtr = false,
  }) {
    final valueWidget = Text(
      value,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 13,
        fontFamily: forceLtr ? 'monospace' : null,
        color: isPass != null
            ? (isPass ? Colors.green.shade700 : Colors.red.shade700)
            : null,
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
          Directionality(textDirection: TextDirection.ltr, child: valueWidget)
        else
          valueWidget,
      ],
    );
  }

  Widget _buildReportViewer(
    String reportText,
    IsharaContinuousSignService service,
  ) {
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
                  Icon(
                    Icons.terminal_rounded,
                    color: Color(0xFF89B4FA),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'ISHARA SIGN RECOGNITION REPORT',
                    style: TextStyle(
                      color: Color(0xFFCDD6F4),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () => _copyReport(service),
                icon: const Icon(
                  Icons.copy_rounded,
                  color: Color(0xFF89B4FA),
                  size: 18,
                ),
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
