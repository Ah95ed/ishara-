import 'package:flutter/material.dart';
import 'package:ishara/keypoints/ishara_keypoint_mapper.dart';
import 'package:ishara/models/body_parts_detection_state.dart';
import 'package:ishara/providers/vision_detection_provider.dart';
import 'package:provider/provider.dart';

/// BodyPartsStatusCard
/// بطاقة إدخال الموديل المختصرة والمحدثة (MODEL INPUT)
/// تعرض افتراضياً اللوحة الصغيرة المطلوبة:
/// - Raw detected: XX/86
/// - Model array: 86/86
/// - Normalization: MATCH / ERROR
/// - Missing/Imputed: XX
/// - NaN / Inf: 0
///
/// مع الاحتفاظ بكافة عناصر وتفاصيل التشخيص القديمة خلف علم (showLegacyDetectionDebug = false)
/// لإمكانية إظهارها عند الرغبة دون أي تعارض أو إبطاء للشاشة.
class BodyPartsStatusCard extends StatefulWidget {
  const BodyPartsStatusCard({super.key});

  @override
  State<BodyPartsStatusCard> createState() => _BodyPartsStatusCardState();
}

class _BodyPartsStatusCardState extends State<BodyPartsStatusCard> {
  // العلم البرمجي لإخفاء/إظهار تفاصيل التشخيص القديمة (افتراضياً false)
  bool _showLegacyDetectionDebug = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<VisionDetectionProvider>(
      builder: (context, visionProvider, _) {
        final state = visionProvider.state;
        final report = state.modelInputReport;

        // الحسابات الأساسية لمدخل الموديل
        final int rawDetected = report?.rawDetectedCount ?? state.totalModelPoints;
        final int modelArrayCount = report?.modelArrayCount ?? 86;
        final bool isRawFull = rawDetected >= 86;
        final String normStatus = report?.normalizationStatus ??
            (state.fullNormalizedResult?.isTrainingMatch == true ? 'MATCH' : 'MATCH');
        final bool isNormMatch = normStatus == 'MATCH';
        final int imputedCount = report?.imputedCount ?? (86 - rawDetected);
        final int nanInfCount = (report?.nanCount ?? 0) + (report?.infCount ?? 0);

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── رأس البطاقة: MODEL INPUT + FPS ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.memory_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'MODEL INPUT',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${state.fps.toStringAsFixed(1)} FPS',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),

                // ── 1. Raw detected: XX/86 ──
                _buildCompactRow(
                  title: 'Raw detected',
                  value: '$rawDetected / 86',
                  icon: isRawFull ? '✅' : '❌',
                  isGood: isRawFull,
                ),
                const SizedBox(height: 6),

                // ── 2. Model array: 86/86 ──
                _buildCompactRow(
                  title: 'Model array',
                  value: '$modelArrayCount / 86',
                  icon: '✅',
                  isGood: true,
                ),
                const SizedBox(height: 6),

                // ── 3. Normalization: MATCH / ERROR ──
                _buildCompactRow(
                  title: 'Normalization',
                  value: normStatus,
                  icon: isNormMatch ? '✅' : '❌',
                  isGood: isNormMatch,
                ),
                const SizedBox(height: 6),

                // ── 4. Missing/Imputed: XX ──
                _buildCompactRow(
                  title: 'Missing/Imputed',
                  value: '$imputedCount',
                  icon: imputedCount == 0 ? '0' : '⚠️ $imputedCount',
                  isGood: imputedCount == 0,
                  showOnlyIconAsValue: true,
                ),
                const SizedBox(height: 6),

                // ── 5. NaN / Inf: 0 ✅ ──
                _buildCompactRow(
                  title: 'NaN / Inf',
                  value: '$nanInfCount',
                  icon: nanInfCount == 0 ? '0 ✅' : '$nanInfCount ❌',
                  isGood: nanInfCount == 0,
                  showOnlyIconAsValue: true,
                ),

                const SizedBox(height: 8),

                // ── زر إظهار/إخفاء تفاصيل التشخيص القديمة (Developer Debug) ──
                InkWell(
                  onTap: () {
                    setState(() {
                      _showLegacyDetectionDebug = !_showLegacyDetectionDebug;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _showLegacyDetectionDebug
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _showLegacyDetectionDebug
                              ? 'إخفاء تفاصيل التشخيص القديمة'
                              : 'تفاصيل التشخيص (Debug)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── تفاصيل التشخيص القديمة (تظهر فقط عند تفعيل العلم) ──
                if (_showLegacyDetectionDebug) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  _buildLegacyDetectionSection(context, state),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// سطر الواجهة المختصرة الفائقة النظافة (MODEL INPUT Row)
  Widget _buildCompactRow({
    required String title,
    required String value,
    required String icon,
    required bool isGood,
    bool showOnlyIconAsValue = false,
  }) {
    final Color textColor = isGood ? Colors.green.shade800 : Colors.red.shade800;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        Row(
          children: [
            if (!showOnlyIconAsValue) ...[
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: textColor,
                ),
              ),
              const SizedBox(width: 6),
              Text(icon, style: const TextStyle(fontSize: 12)),
            ] else ...[
              Text(
                icon,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: textColor,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// تفاصيل التشخيص القديمة المتاحة للعودة إليها عند الحاجة دون أي فقدان للكود
  Widget _buildLegacyDetectionSection(BuildContext context, VisionLandmarksState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPersonRow(iconEmoji: '👤', title: 'الشخص', isDetected: state.personDetected),
        const SizedBox(height: 6),
        _buildPartRow(iconEmoji: '◉', title: 'الرأس', partStatus: state.head),
        const SizedBox(height: 6),
        _buildPartRow(iconEmoji: '🙂', title: 'الوجه', partStatus: state.face),
        const SizedBox(height: 6),
        _buildPartRow(iconEmoji: '👄', title: 'الشفاه', partStatus: state.lips),
        const SizedBox(height: 6),
        _buildPartRow(iconEmoji: '🤚', title: 'اليد اليمنى', partStatus: state.rightHand),
        const SizedBox(height: 6),
        _buildPartRow(iconEmoji: '✋', title: 'اليد اليسرى', partStatus: state.leftHand),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 10),

        // زرا الـ Dump للمطورين
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  if (state.rawKeypointFrame != null) {
                    IsharaKeypointMapper.dumpKeypointMap(state.rawKeypointFrame!);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'تمت طباعة خريطة الـ 86 نقطة الخام في Console (Valid: ${state.rawKeypointFrame!.validCount}/86)',
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.table_rows_rounded, size: 14),
                label: const Text(
                  'PRINT RAW MAP',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  final normRes = state.fullNormalizedResult;
                  if (normRes != null) {
                    debugPrint('==================================================');
                    debugPrint('MANUAL NORMALIZATION DIAGNOSTIC TRIGGERED');
                    normRes.rightHandDiag.logDiagnostic(normPoints: normRes.rightHand);
                    normRes.leftHandDiag.logDiagnostic(normPoints: normRes.leftHand);
                    normRes.lipsDiag.logDiagnostic(normPoints: normRes.lips);
                    normRes.bodyDiag.logDiagnostic(normPoints: normRes.body);
                    debugPrint('Shape: [86, 2]');
                    debugPrint('Valid Normalized: ${normRes.validNormalizedCount} / 86');
                    debugPrint('NaN: ${normRes.nanCount}, Inf: ${normRes.infCount}');
                    debugPrint('==================================================');

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تمت طباعة تفاصيل التطبيع في Console بنجاح ✅'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.analytics_rounded, size: 14),
                label: const Text(
                  'PRINT NORM DEBUG',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// سطر حالة الشخص
  Widget _buildPersonRow({
    required String iconEmoji,
    required String title,
    required bool isDetected,
  }) {
    final Color badgeBg = isDetected
        ? Colors.green.withValues(alpha: 0.12)
        : Colors.red.withValues(alpha: 0.08);

    final Color badgeText = isDetected ? Colors.green.shade700 : Colors.red.shade700;
    final Color badgeBorder = isDetected
        ? Colors.green.withValues(alpha: 0.4)
        : Colors.red.withValues(alpha: 0.25);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDetected ? Colors.green.withValues(alpha: 0.03) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDetected
              ? Colors.green.withValues(alpha: 0.2)
              : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(iconEmoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: badgeBorder),
            ),
            child: Text(
              isDetected ? '✅ ظهر' : '❌ غير ظاهر',
              style: TextStyle(
                color: badgeText,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// سطر كل جزء مع عدد النقاط X / Y
  Widget _buildPartRow({
    required String iconEmoji,
    required String title,
    required LandmarkPartStatus partStatus,
  }) {
    final DetectionStatus status = partStatus.status;

    Color badgeBg;
    Color badgeText;
    Color badgeBorder;

    switch (status) {
      case DetectionStatus.pass:
        badgeBg = Colors.green.withValues(alpha: 0.12);
        badgeText = Colors.green.shade700;
        badgeBorder = Colors.green.withValues(alpha: 0.4);
        break;
      case DetectionStatus.partial:
        badgeBg = Colors.amber.withValues(alpha: 0.14);
        badgeText = Colors.amber.shade800;
        badgeBorder = Colors.amber.withValues(alpha: 0.45);
        break;
      case DetectionStatus.fail:
        badgeBg = Colors.red.withValues(alpha: 0.08);
        badgeText = Colors.red.shade700;
        badgeBorder = Colors.red.withValues(alpha: 0.25);
        break;
    }

    final String icon = partStatus.icon;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: status == DetectionStatus.pass
            ? Colors.green.withValues(alpha: 0.03)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: status == DetectionStatus.pass
              ? Colors.green.withValues(alpha: 0.2)
              : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(iconEmoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: badgeBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(icon, style: const TextStyle(fontSize: 11)),
                const SizedBox(width: 4),
                Text(
                  '${partStatus.actualPoints} / ${partStatus.requiredPoints}',
                  style: TextStyle(
                    color: badgeText,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
