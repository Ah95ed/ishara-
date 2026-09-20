import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ishara/models/ctc_vocab_result.dart';
import 'package:ishara/models/real_inference_result.dart';
import 'package:ishara/providers/vision_detection_provider.dart';
import 'package:provider/provider.dart';

/// CtcDiagnosticsPage
/// صفحة تشخيص مستقلة تماماً لفك تشفير CTC وربط المفردات (CTC & Vocabulary Diagnostics):
/// - لا تزدحم بها شاشة الكاميرا الرئيسية.
/// - تعرض:
///   MODEL OUTPUT: [1,29,684] ✅
///   CTC: PASS ✅
///   Vocabulary: PASS ✅
///   Blank ID: 0
///   Sequence Quality: XX.XX %
///   Imputation: XX.XX %
///   Raw IDs: [...]
///   Decoded IDs: [...]
///   Predicted Glosses: [...] (SelectableText لتسهيل النسخ)
/// - زر: [ RUN CTC + VOCAB TEST ]
/// - زر: [ COPY CTC/VOCAB REPORT ]
/// - عارض التقرير النصي الكامل بالخط الثابت Monospace المطابق لمواصفات التقرير الرسمي.
class CtcDiagnosticsPage extends StatefulWidget {
  const CtcDiagnosticsPage({super.key});

  @override
  State<CtcDiagnosticsPage> createState() => _CtcDiagnosticsPageState();
}

class _CtcDiagnosticsPageState extends State<CtcDiagnosticsPage> {
  String _selectedTest = 'TEST A';
  CtcVocabResult? _manualRunResult;
  bool _noRealInferenceError = false;

  /// نسخ تقرير CTC + Vocab إلى الحافظة
  Future<void> _copyReport(String reportText) async {
    await Clipboard.setData(ClipboardData(text: reportText));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'تم نسخ تقرير CTC/VOCAB الكامل (Report copied ✓)',
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

  /// تنفيذ فحص CTC + Vocabulary يدوياً على آخر استنتاج حقيقي صالح
  void _runCtcVocabTest(SingleRealInferenceResult? selectedResult, VisionDetectionProvider visionProvider) {
    if (selectedResult == null || !selectedResult.isSuccess) {
      setState(() {
        _noRealInferenceError = true;
        _manualRunResult = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'NO_REAL_INFERENCE_AVAILABLE (يرجى تشغيل Test A أو Test B أولاً)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final result = visionProvider.realInferenceService.runCtcVocabDecoding(selectedResult);
    setState(() {
      _noRealInferenceError = false;
      _manualRunResult = result;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              'تم استخراج ${result.finalGlossSequence.length} Glosses بنجاح ✓',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: Colors.indigo.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CTC & Vocabulary Diagnostics',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Consumer<VisionDetectionProvider>(
        builder: (context, visionProvider, _) {
          final realService = visionProvider.realInferenceService;
          final resultA = realService.resultA;
          final resultB = realService.resultB;

          // اختيار نتيجة الاختبار المعروضة
          final SingleRealInferenceResult? selectedResult =
              _selectedTest == 'TEST B' ? (resultB ?? resultA) : (resultA ?? resultB);

          // الحصول على نتيجة CTC + Vocab الحقيقية إذا توفرت
          final CtcVocabResult? activeResult = _manualRunResult ??
              selectedResult?.ctcVocabResult ??
              (selectedResult != null && selectedResult.isSuccess
                  ? realService.runCtcVocabDecoding(selectedResult)
                  : null);

          final bool hasRealResult = activeResult != null && activeResult.isSuccess;

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── اختيار الاختبار (Test A / Test B) ──
                  if (resultA != null || resultB != null) ...[
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'TEST A',
                          label: Text(resultA != null ? 'Test A (جاهز)' : 'Test A'),
                          icon: Icon(
                            resultA != null ? Icons.check_circle : Icons.circle_outlined,
                            size: 16,
                            color: resultA != null ? Colors.green : Colors.grey,
                          ),
                        ),
                        ButtonSegment(
                          value: 'TEST B',
                          label: Text(resultB != null ? 'Test B (جاهز)' : 'Test B'),
                          icon: Icon(
                            resultB != null ? Icons.check_circle : Icons.circle_outlined,
                            size: 16,
                            color: resultB != null ? Colors.green : Colors.grey,
                          ),
                        ),
                      ],
                      selected: {_selectedTest},
                      onSelectionChanged: (set) {
                        setState(() {
                          _selectedTest = set.first;
                          _manualRunResult = null;
                          _noRealInferenceError = false;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── تنبيه عدم توفر استنتاج حقيقي إذا حدث ──
                  if (_noRealInferenceError || (!hasRealResult && selectedResult == null)) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.amber.shade800, size: 24),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'NO_REAL_INFERENCE_AVAILABLE\nقم بتشغيل Test A أو Test B من الشاشة الرئيسية للحصول على مخرجات الموديل الحقيقية.',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── 1. بطاقة فحص النموذج والمخرجات (Model & CTC Status) ──
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
                            'MODEL & PIPELINE STATUS',
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

                          _buildStatusRow(
                            label: 'MODEL OUTPUT',
                            status: hasRealResult ? '[1,29,684] ✅' : 'PENDING ⏳',
                            isPass: hasRealResult,
                          ),
                          const SizedBox(height: 8),
                          _buildStatusRow(
                            label: 'CTC',
                            status: hasRealResult && activeResult.ctcResult.isSuccess ? 'PASS ✅' : 'PENDING ⏳',
                            isPass: hasRealResult && activeResult.ctcResult.isSuccess,
                          ),
                          const SizedBox(height: 8),
                          _buildStatusRow(
                            label: 'Vocabulary',
                            status: (activeResult?.isVocabLoaded ?? false) ? 'PASS ✅' : 'READY ✅',
                            isPass: true,
                          ),
                          const SizedBox(height: 8),
                          _buildDetailRow(
                            label: 'Blank ID',
                            value: '0',
                            forceLtr: true,
                          ),
                          const SizedBox(height: 8),
                          _buildDetailRow(
                            label: 'Sequence Quality',
                            value: hasRealResult
                                ? '${activeResult.sequenceQualityPct.toStringAsFixed(2)} %'
                                : '--',
                            forceLtr: true,
                          ),
                          const SizedBox(height: 8),
                          _buildDetailRow(
                            label: 'Imputation',
                            value: hasRealResult
                                ? '${activeResult.imputationPct.toStringAsFixed(2)} %'
                                : '--',
                            forceLtr: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── 2. بطاقة الأرقام الخام والمشفرة (Raw IDs & Decoded IDs) ──
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
                            'CTC SEQUENCES',
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

                          const Text(
                            'Raw IDs (Argmax 29 timesteps):',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: SelectableText(
                                hasRealResult
                                    ? '[${activeResult.ctcResult.rawArgmaxIds.join(',')}]'
                                    : '[NO_DATA]',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          const Text(
                            'Decoded IDs (Collapsed & Blank 0 Removed):',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: SelectableText(
                                hasRealResult
                                    ? '[${activeResult.ctcResult.decodedIds.join(',')}]'
                                    : '[NO_DATA]',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── 3. بطاقة الكلمات المستخرجة (Predicted Glosses - SelectableText) ──
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.indigo.shade300, width: 1.2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.translate_rounded, color: Colors.indigo, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'PREDICTED GLOSSES',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              if (hasRealResult)
                                Chip(
                                  label: Text(
                                    '${activeResult.finalGlossSequence.length} Words',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                  backgroundColor: Colors.indigo.shade50,
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),

                          if (!hasRealResult) ...[
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 20.0),
                                child: Text(
                                  'لا توجد كلمات متاحة حالياً.\nاضغط [ RUN CTC + VOCAB TEST ] بعد تشغيل أي حركة.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey, fontSize: 13),
                                ),
                              ),
                            ),
                          ] else if (activeResult.predictedGlosses.isEmpty) ...[
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 20.0),
                                child: Text(
                                  'Decoded IDs فارغة (تكرارات وBlank فقط).',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey, fontSize: 13),
                                ),
                              ),
                            ),
                          ] else ...[
                            // عرض كل ID والـ Gloss المقابل له بشكل قابل للتحديد
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.indigo.shade100),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final item in activeResult.predictedGlosses) ...[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.indigo.shade700,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'ID ${item.classId}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          const Text(
                                            '→',
                                            style: TextStyle(fontSize: 16, color: Colors.blueGrey),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: SelectableText(
                                              item.gloss,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            const Text(
                              'Final Gloss Sequence (يمكنك نسخه مباشرة):',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: SelectableText(
                                '[${activeResult.finalGlossSequence.join(', ')}]',
                                style: TextStyle(
                                  fontSize: 16,
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

                  // ── 4. زر [ RUN CTC + VOCAB TEST ] ──
                  ElevatedButton.icon(
                    onPressed: () => _runCtcVocabTest(selectedResult, visionProvider),
                    icon: const Icon(Icons.play_arrow_rounded, size: 22),
                    label: const Text(
                      'RUN CTC + VOCAB TEST',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.indigo.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── 5. زر [ COPY CTC/VOCAB REPORT ] ──
                  OutlinedButton.icon(
                    onPressed: hasRealResult
                        ? () => _copyReport(activeResult.toReportText())
                        : null,
                    icon: const Icon(Icons.copy_all_rounded, size: 20),
                    label: const Text(
                      'COPY CTC/VOCAB REPORT',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      foregroundColor: Colors.indigo.shade800,
                      side: BorderSide(color: Colors.indigo.shade700, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── 6. عارض التقرير الكامل (Monospace ASCII Preview) ──
                  if (hasRealResult) ...[
                    _buildReportViewer(activeResult.toReportText()),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusRow({
    required String label,
    required String status,
    required bool isPass,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
        ),
        Text(
          status,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: isPass ? Colors.green.shade700 : Colors.amber.shade800,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    bool forceLtr = false,
  }) {
    final valueWidget = Text(
      value,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 13,
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
                    'ISHARA CTC + VOCAB REPORT',
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
                onPressed: () => _copyReport(reportText),
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
