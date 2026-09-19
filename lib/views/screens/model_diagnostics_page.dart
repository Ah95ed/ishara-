import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ishara/models/model_smoke_test_result.dart';
import 'package:ishara/services/ishara_model_smoke_test_service.dart';

/// ModelDiagnosticsPage
/// صفحة فحص وتشخيص نموذج الذكاء الاصطناعي TFLite المستقلة (Model Smoke Test).
class ModelDiagnosticsPage extends StatefulWidget {
  const ModelDiagnosticsPage({super.key});

  @override
  State<ModelDiagnosticsPage> createState() => _ModelDiagnosticsPageState();
}

class _ModelDiagnosticsPageState extends State<ModelDiagnosticsPage> {
  final IsharaModelSmokeTestService _smokeTestService = IsharaModelSmokeTestService();

  bool _isTesting = false;
  ModelSmokeTestResult? _result;
  String? _reportText;

  /// تنفيذ فحص الدخان للنموذج
  Future<void> _runModelTest() async {
    if (_isTesting) return;

    setState(() {
      _isTesting = true;
    });

    try {
      final result = await _smokeTestService.runSmokeTest();
      final text = result.toReportText();

      setState(() {
        _result = result;
        _reportText = text;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء الفحص: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  /// نسخ التقرير إلى الحافظة
  Future<void> _copyReport() async {
    if (_reportText == null) return;

    await Clipboard.setData(ClipboardData(text: _reportText!));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('تم نسخ تقرير الموديل', style: TextStyle(fontWeight: FontWeight.bold)),
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
    // استخراج القيم لحاوية MODEL STATUS
    final String modelFileStatus = _isTesting
        ? 'TESTING...'
        : (_result == null
            ? 'WAITING'
            : (_result!.fileValidationPass ? 'VALID' : 'ERROR'));

    final String interpreterStatus = _isTesting
        ? 'TESTING...'
        : (_result == null
            ? 'WAITING'
            : (_result!.interpreterReady ? 'READY' : 'ERROR'));

    final String inputStr = _isTesting
        ? '...'
        : (_result?.actualInputShape != null
            ? _result!.actualInputShape.toString().replaceAll(' ', '')
            : '--');

    final String outputStr = _isTesting
        ? '...'
        : (_result?.actualOutputShape != null
            ? _result!.actualOutputShape.toString().replaceAll(' ', '')
            : '--');

    final String inferenceStr = _isTesting
        ? '...'
        : (_result != null && _result!.zeroInferencePass
            ? '${_result!.zeroInferenceTimeMs} ms'
            : '--');

    final String overallStatusBadge = _isTesting
        ? 'TESTING'
        : (_result == null ? 'READY TO TEST' : (_result!.isOverallPass ? 'PASS' : 'FAIL'));

    final Color badgeColor = _isTesting
        ? Colors.amber.shade700
        : (_result == null
            ? Colors.grey.shade600
            : (_result!.isOverallPass ? Colors.green.shade700 : Colors.red.shade700));

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Model Diagnostics',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1. بطاقة MODEL STATUS ──
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'MODEL STATUS',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              overallStatusBadge,
                              style: TextStyle(
                                color: badgeColor,
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

                      _buildStatusRow(
                        title: 'Model File',
                        value: modelFileStatus,
                        isGood: modelFileStatus == 'VALID',
                        isBad: modelFileStatus == 'ERROR',
                      ),
                      const SizedBox(height: 6),
                      _buildStatusRow(
                        title: 'Interpreter',
                        value: interpreterStatus,
                        isGood: interpreterStatus == 'READY',
                        isBad: interpreterStatus == 'ERROR',
                      ),
                      const SizedBox(height: 6),
                      _buildStatusRow(
                        title: 'Input',
                        value: inputStr,
                        forceLtr: true,
                      ),
                      const SizedBox(height: 6),
                      _buildStatusRow(
                        title: 'Output',
                        value: outputStr,
                        forceLtr: true,
                      ),
                      const SizedBox(height: 6),
                      _buildStatusRow(
                        title: 'Inference',
                        value: inferenceStr,
                        forceLtr: true,
                        isGood: _result?.zeroInferencePass == true,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ── 2. أزرار التحكم: [ RUN MODEL TEST ] و [ COPY REPORT ] ──
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: _isTesting ? null : _runModelTest,
                      icon: _isTesting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 20),
                      label: Text(
                        _isTesting ? 'TESTING...' : 'RUN MODEL TEST',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: (_isTesting || _reportText == null) ? null : _copyReport,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text(
                        'COPY REPORT',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ── 3. منطقة عرض التقرير SelectableText داخل SingleChildScrollView ──
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _isTesting
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 14),
                                Text(
                                  'جاري فحص الموديل وتشغيل الاستنتاج التجريبي...',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          )
                        : (_reportText == null
                            ? Center(
                                child: Text(
                                  'اضغط على [ RUN MODEL TEST ] لبدء الفحص وإظهار التقرير',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : Directionality(
                                textDirection: TextDirection.ltr,
                                child: Scrollbar(
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(14),
                                    child: SelectableText(
                                      _reportText!,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ),
                              )),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// سطر بسيط داخل بطاقة MODEL STATUS
  Widget _buildStatusRow({
    required String title,
    required String value,
    bool isGood = false,
    bool isBad = false,
    bool forceLtr = false,
  }) {
    Color valueColor = Colors.grey.shade800;
    if (isGood) valueColor = Colors.green.shade700;
    if (isBad) valueColor = Colors.red.shade700;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
        ),
        Directionality(
          textDirection: forceLtr ? TextDirection.ltr : Directionality.of(context),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: valueColor,
              fontFamily: forceLtr ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}
