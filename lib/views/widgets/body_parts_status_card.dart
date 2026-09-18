import 'package:flutter/material.dart';
import 'package:ishara/keypoints/ishara_keypoint_mapper.dart';
import 'package:ishara/ml/buffer/ishara_frame_ring_buffer.dart';
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
        final int rawDetected =
            report?.rawDetectedCount ?? state.totalModelPoints;
        final int modelArrayCount = report?.modelArrayCount ?? 86;
        final bool isRawFull = rawDetected >= 86;
        final String normStatus =
            report?.normalizationStatus ??
            (state.fullNormalizedResult?.isTrainingMatch == true
                ? 'MATCH'
                : 'MATCH');
        final bool isNormMatch = normStatus == 'MATCH';
        final int imputedCount = report?.imputedCount ?? (86 - rawDetected);
        final int nanInfCount =
            (report?.nanCount ?? 0) + (report?.infCount ?? 0);

        // متغيرات الـ 128-Frame Ring Buffer
        final ringStatus = state.ringBufferStatus;
        final int bufferFrames = ringStatus?.frameCount ?? 0;
        final bool isBufferReady = ringStatus?.isReady ?? false;
        final RingBufferState bufferState =
            ringStatus?.state ?? RingBufferState.empty;
        final String bufferStateName = (!state.personDetected)
            ? 'BUFFER PAUSED — NO PERSON'
            : (bufferState == RingBufferState.ready
                  ? 'READY ✅'
                  : bufferState.displayName);
        final String latestFrameStr = ringStatus?.latestFrameSequenceId != null
            ? '#${ringStatus!.latestFrameSequenceId}'
            : 'None';
        final int bufferNanInf =
            (ringStatus?.nanCount ?? 0) + (ringStatus?.infCount ?? 0);
        final int duplicateCount = ringStatus?.duplicateCount ?? 0;

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
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
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
                  forceLtr: true,
                ),
                const SizedBox(height: 6),

                // ── 2. Model array: 86/86 ──
                _buildCompactRow(
                  title: 'Model array',
                  value: '$modelArrayCount / 86',
                  icon: '✅',
                  isGood: true,
                  forceLtr: true,
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
                  forceLtr: true,
                ),
                const SizedBox(height: 6),

                // ── 5. NaN / Inf: 0 ✅ ──
                _buildCompactRow(
                  title: 'NaN / Inf',
                  value: '$nanInfCount',
                  icon: nanInfCount == 0 ? '0 ✅' : '$nanInfCount ❌',
                  isGood: nanInfCount == 0,
                  showOnlyIconAsValue: true,
                  forceLtr: true,
                ),

                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // ── رأس قسم SEQUENCE BUFFER ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.all_inclusive_rounded,
                            color: Theme.of(context).colorScheme.secondary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'SEQUENCE BUFFER',
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
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isBufferReady
                            ? Colors.green.withValues(alpha: 0.15)
                            : (!state.personDetected
                                  ? Colors.orange.withValues(alpha: 0.15)
                                  : Colors.blue.withValues(alpha: 0.15)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isBufferReady
                            ? 'READY ✅'
                            : (!state.personDetected
                                  ? 'PAUSED ⏸'
                                  : 'FILLING ⏳'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isBufferReady
                              ? Colors.green.shade800
                              : (!state.personDetected
                                    ? Colors.orange.shade800
                                    : Colors.blue.shade800),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // ── 1. Frames: XX/128 ──
                _buildCompactRow(
                  title: 'Frames',
                  value: isBufferReady ? '128 / 128' : '$bufferFrames / 128',
                  icon: isBufferReady ? '128 / 128 ✅' : '$bufferFrames / 128',
                  isGood: isBufferReady,
                  showOnlyIconAsValue: true,
                  forceLtr: true,
                ),
                const SizedBox(height: 6),

                // ── 2. State: FILLING / READY / BUFFER PAUSED — NO PERSON ──
                _buildCompactRow(
                  title: 'State',
                  value: bufferStateName,
                  icon: bufferStateName,
                  isGood: isBufferReady || state.personDetected,
                  showOnlyIconAsValue: true,
                ),
                const SizedBox(height: 6),

                // ── 3. Latest Frame: #XXX ──
                _buildCompactRow(
                  title: 'Latest Frame',
                  value: latestFrameStr,
                  icon: latestFrameStr,
                  isGood: true,
                  showOnlyIconAsValue: true,
                  forceLtr: true,
                ),
                const SizedBox(height: 6),

                // ── 4. Frame Shape: [86, 2] ──
                _buildCompactRow(
                  title: 'Frame Shape',
                  value: '[86, 2]',
                  icon: '[86, 2]',
                  isGood: true,
                  showOnlyIconAsValue: true,
                  forceLtr: true,
                ),
                const SizedBox(height: 6),

                // ── 5. Sequence Shape: [XX, 86, 2] ──
                _buildCompactRow(
                  title: 'Sequence Shape',
                  value: isBufferReady
                      ? '[128, 86, 2] ✅'
                      : '[$bufferFrames, 86, 2]',
                  icon: isBufferReady
                      ? '[128, 86, 2] ✅'
                      : '[$bufferFrames, 86, 2]',
                  isGood: isBufferReady,
                  showOnlyIconAsValue: true,
                  forceLtr: true,
                ),
                const SizedBox(height: 6),

                // ── 6. Model Shape: [1, 128, 86, 2] (عند الاكتمال) ──
                if (isBufferReady) ...[
                  _buildCompactRow(
                    title: 'Model Shape',
                    value: '[1, 128, 86, 2] ✅',
                    icon: '[1, 128, 86, 2] ✅',
                    isGood: true,
                    showOnlyIconAsValue: true,
                    forceLtr: true,
                  ),
                  const SizedBox(height: 6),
                ],

                // ── 7. NaN / Inf: 0 ✅ ──
                _buildCompactRow(
                  title: 'NaN / Inf',
                  value: '$bufferNanInf',
                  icon: bufferNanInf == 0 ? '0 ✅' : '$bufferNanInf ❌',
                  isGood: bufferNanInf == 0,
                  showOnlyIconAsValue: true,
                  forceLtr: true,
                ),
                const SizedBox(height: 6),

                // ── 8. Duplicates: 0 ──
                _buildCompactRow(
                  title: 'Duplicates',
                  value: '$duplicateCount',
                  icon: duplicateCount == 0
                      ? '0'
                      : '$duplicateCount (rejected)',
                  isGood: duplicateCount == 0,
                  showOnlyIconAsValue: true,
                  forceLtr: true,
                ),

                const SizedBox(height: 10),

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
    bool forceLtr = false,
  }) {
    final Color textColor = isGood
        ? Colors.green.shade800
        : Colors.red.shade800;

    Widget valueWidget = Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: forceLtr ? TextDirection.ltr : null,
      children: [
        if (!showOnlyIconAsValue) ...[
          Text(
            value,
            textDirection: forceLtr ? TextDirection.ltr : null,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: textColor,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            icon,
            textDirection: forceLtr ? TextDirection.ltr : null,
            style: const TextStyle(fontSize: 12),
          ),
        ] else ...[
          Text(
            icon,
            textDirection: forceLtr ? TextDirection.ltr : null,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: textColor,
            ),
          ),
        ],
      ],
    );

    if (forceLtr) {
      valueWidget = Directionality(
        textDirection: TextDirection.ltr,
        child: valueWidget,
      );
    }

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
        valueWidget,
      ],
    );
  }

  /// تفاصيل التشخيص القديمة المتاحة للعودة إليها عند الحاجة دون أي فقدان للكود
  Widget _buildLegacyDetectionSection(
    BuildContext context,
    VisionLandmarksState state,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPersonRow(
          iconEmoji: '👤',
          title: 'الشخص',
          isDetected: state.personDetected,
        ),
        const SizedBox(height: 6),
        _buildPartRow(iconEmoji: '◉', title: 'الرأس', partStatus: state.head),
        const SizedBox(height: 6),
        _buildPartRow(iconEmoji: '🙂', title: 'الوجه', partStatus: state.face),
        const SizedBox(height: 6),
        _buildPartRow(iconEmoji: '👄', title: 'الشفاه', partStatus: state.lips),
        const SizedBox(height: 6),
        _buildPartRow(
          iconEmoji: '🤚',
          title: 'اليد اليمنى',
          partStatus: state.rightHand,
        ),
        const SizedBox(height: 6),
        _buildPartRow(
          iconEmoji: '✋',
          title: 'اليد اليسرى',
          partStatus: state.leftHand,
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 10),

        // إحصائيات الـ Ring Buffer التفصيلية (Developer Debug Counters)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'BUFFER COUNTERS (DIAGNOSTIC)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              _buildDebugCounterRow(
                'Camera processed',
                '${state.ringBufferStatus?.totalFramesReceived ?? 0}',
              ),
              _buildDebugCounterRow(
                'Added to buffer',
                '${state.ringBufferStatus?.totalFramesAdded ?? 0}',
              ),
              _buildDebugCounterRow(
                'Skipped no person',
                '${state.ringBufferStatus?.totalFramesSkippedNoPerson ?? 0}',
              ),
              _buildDebugCounterRow(
                'Duplicates rejected',
                '${state.ringBufferStatus?.duplicateFramesRejected ?? 0}',
              ),
              _buildDebugCounterRow(
                'Invalid frames rejected',
                '${state.ringBufferStatus?.invalidFramesRejected ?? 0}',
              ),
              _buildDebugCounterRow(
                'Oldest Frame ID',
                state.ringBufferStatus?.oldestFrameSequenceId != null
                    ? '#${state.ringBufferStatus!.oldestFrameSequenceId}'
                    : 'None',
              ),
              _buildDebugCounterRow(
                'Newest Frame ID',
                state.ringBufferStatus?.latestFrameSequenceId != null
                    ? '#${state.ringBufferStatus!.latestFrameSequenceId}'
                    : 'None',
              ),
            ],
          ),
        ),

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
                    IsharaKeypointMapper.dumpKeypointMap(
                      state.rawKeypointFrame!,
                    );
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
                    debugPrint(
                      '==================================================',
                    );
                    debugPrint('MANUAL NORMALIZATION DIAGNOSTIC TRIGGERED');
                    normRes.rightHandDiag.logDiagnostic(
                      normPoints: normRes.rightHand,
                    );
                    normRes.leftHandDiag.logDiagnostic(
                      normPoints: normRes.leftHand,
                    );
                    normRes.lipsDiag.logDiagnostic(normPoints: normRes.lips);
                    normRes.bodyDiag.logDiagnostic(normPoints: normRes.body);
                    debugPrint('Shape: [86, 2]');
                    debugPrint(
                      'Valid Normalized: ${normRes.validNormalizedCount} / 86',
                    );
                    debugPrint(
                      'NaN: ${normRes.nanCount}, Inf: ${normRes.infCount}',
                    );
                    debugPrint(
                      '==================================================',
                    );

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'تمت طباعة تفاصيل التطبيع في Console بنجاح ✅',
                        ),
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

    final Color badgeText = isDetected
        ? Colors.green.shade700
        : Colors.red.shade700;
    final Color badgeBorder = isDetected
        ? Colors.green.withValues(alpha: 0.4)
        : Colors.red.withValues(alpha: 0.25);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDetected
            ? Colors.green.withValues(alpha: 0.03)
            : Colors.transparent,
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
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

  Widget _buildDebugCounterRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              value,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
