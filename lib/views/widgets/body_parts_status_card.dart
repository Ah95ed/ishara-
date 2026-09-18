import 'package:flutter/material.dart';
import 'package:ishara/keypoints/ishara_keypoint_mapper.dart';
import 'package:ishara/ml/buffer/ishara_frame_ring_buffer.dart';
import 'package:ishara/ml/model/ishara_tflite_service.dart';
import 'package:ishara/models/body_parts_detection_state.dart';
import 'package:ishara/providers/vision_detection_provider.dart';
import 'package:provider/provider.dart';

/// BodyPartsStatusCard
/// بطاقة خط أنابيب الموديل المحدثة (MODEL PIPELINE)
/// تعرض افتراضياً اللوحة الصغيرة المطلوبة فقط:
/// - Buffer: 128/128 ✅
/// - Model: LOADING / READY / ERROR
/// - Input: [1, 128, 86, 2]
/// - Output: [1, 29, 684]
/// - Inference: XX ms
/// - Output Valid: YES / NO
///
/// مع الاحتفاظ بكافة عناصر وتفاصيل التشخيص السابقة كاملةً خلف (showDeveloperDebug = false)
/// لإمكانية إظهارها عند الرغبة دون أي تعارض أو إبطاء للشاشة.
class BodyPartsStatusCard extends StatefulWidget {
  const BodyPartsStatusCard({super.key});

  @override
  State<BodyPartsStatusCard> createState() => _BodyPartsStatusCardState();
}

class _BodyPartsStatusCardState extends State<BodyPartsStatusCard> {
  // العلم البرمجي لإخفاء/إظهار تفاصيل التشخيص القديمة (افتراضياً false)
  bool _showDeveloperDebug = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<VisionDetectionProvider>(
      builder: (context, visionProvider, _) {
        final state = visionProvider.state;
        final report = state.modelInputReport;

        // ── بيانات الـ Ring Buffer ──
        final ringStatus = state.ringBufferStatus;
        final int bufferFrames = ringStatus?.frameCount ?? 0;
        final bool isBufferReady = ringStatus?.isReady ?? false;
        final String bufferStr = isBufferReady ? '128 / 128' : '$bufferFrames / 128';

        // ── بيانات الـ TFLite Model Pipeline ──
        final modelPipe = state.modelPipelineStatus;
        final ModelLoadState modelState = modelPipe?.state ?? ModelLoadState.notLoaded;
        final String modelStateStr = modelState == ModelLoadState.ready
            ? 'READY'
            : (modelState == ModelLoadState.loading
                ? 'LOADING ⏳'
                : (modelState == ModelLoadState.error
                    ? 'ERROR ❌'
                    : 'NOT_LOADED'));

        final String inputShapeStr = '[1, 128, 86, 2]';
        final String outputShapeStr = '[1, 29, 684]';

        final String inferenceTimeStr = (modelPipe != null && modelPipe.lastInferenceTimeMs > 0)
            ? '${modelPipe.lastInferenceTimeMs} ms'
            : '-- ms';

        final String outputValidStr = (modelPipe != null && modelPipe.totalInferenceCount > 0)
            ? (modelPipe.isLastOutputValid ? 'YES' : 'NO')
            : '--';

        // ── بيانات التشخيص المتقدمة للـ Developer Debug ──
        final int rawDetected = report?.rawDetectedCount ?? state.totalModelPoints;
        final int modelArrayCount = report?.modelArrayCount ?? 86;
        final bool isRawFull = rawDetected >= 86;
        final String normStatus = report?.normalizationStatus ??
            (state.fullNormalizedResult?.isTrainingMatch == true ? 'MATCH' : 'MATCH');
        final bool isNormMatch = normStatus == 'MATCH';
        final int imputedCount = report?.imputedCount ?? (86 - rawDetected);
        final int nanInfCount = (report?.nanCount ?? 0) + (report?.infCount ?? 0);

        final RingBufferState bufferState = ringStatus?.state ?? RingBufferState.empty;
        final String bufferStateName = (!state.personDetected)
            ? 'BUFFER PAUSED — NO PERSON'
            : (bufferState == RingBufferState.ready ? 'READY ✅' : bufferState.displayName);
        final String latestFrameStr = ringStatus?.latestFrameSequenceId != null
            ? '#${ringStatus!.latestFrameSequenceId}'
            : 'None';
        final int bufferNanInf = (ringStatus?.nanCount ?? 0) + (ringStatus?.infCount ?? 0);
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
                // ── رأس البطاقة: MODEL PIPELINE + FPS ──
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
                            Icons.psychology_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'MODEL PIPELINE',
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

                // ── 1. Buffer: 128/128 ✅ ──
                _buildCompactRow(
                  title: 'Buffer',
                  value: bufferStr,
                  icon: isBufferReady ? '128 / 128 ✅' : '$bufferFrames / 128',
                  isGood: isBufferReady,
                  showOnlyIconAsValue: true,
                  forceLtr: true,
                ),
                const SizedBox(height: 6),

                // ── 2. Model: LOADING / READY / ERROR ──
                _buildCompactRow(
                  title: 'Model',
                  value: modelStateStr,
                  icon: modelState == ModelLoadState.ready ? '$modelStateStr ✅' : modelStateStr,
                  isGood: modelState == ModelLoadState.ready,
                  showOnlyIconAsValue: true,
                  forceLtr: true,
                ),
                const SizedBox(height: 6),

                // ── 3. Input: [1, 128, 86, 2] ──
                _buildCompactRow(
                  title: 'Input',
                  value: inputShapeStr,
                  icon: inputShapeStr,
                  isGood: true,
                  showOnlyIconAsValue: true,
                  forceLtr: true,
                ),
                const SizedBox(height: 6),

                // ── 4. Output: [1, 29, 684] ──
                _buildCompactRow(
                  title: 'Output',
                  value: outputShapeStr,
                  icon: outputShapeStr,
                  isGood: true,
                  showOnlyIconAsValue: true,
                  forceLtr: true,
                ),
                const SizedBox(height: 6),

                // ── 5. Inference: XX ms ──
                _buildCompactRow(
                  title: 'Inference',
                  value: inferenceTimeStr,
                  icon: inferenceTimeStr,
                  isGood: modelPipe != null && modelPipe.lastInferenceTimeMs > 0,
                  showOnlyIconAsValue: true,
                  forceLtr: true,
                ),
                const SizedBox(height: 6),

                // ── 6. Output Valid: YES / NO ──
                _buildCompactRow(
                  title: 'Output Valid',
                  value: outputValidStr,
                  icon: outputValidStr == 'YES' ? 'YES ✅' : (outputValidStr == 'NO' ? 'NO ❌' : '--'),
                  isGood: outputValidStr == 'YES',
                  showOnlyIconAsValue: true,
                  forceLtr: true,
                ),

                const SizedBox(height: 12),

                // ── زر تشغيل الاستنتاج اليدوي / التشخيصي ──
                ElevatedButton.icon(
                  onPressed: (!isBufferReady || modelState != ModelLoadState.ready)
                      ? null
                      : () async {
                          await visionProvider.runModelInference();
                        },
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: Text(
                    isBufferReady ? 'RUN INFERENCE (تشغيل الاستنتاج)' : 'BUFFER FILLING (${bufferFrames}/128)...',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),

                const SizedBox(height: 8),

                // ── زر إظهار/إخفاء تفاصيل التشخيص (Developer Debug) ──
                InkWell(
                  onTap: () {
                    setState(() {
                      _showDeveloperDebug = !_showDeveloperDebug;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _showDeveloperDebug
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _showDeveloperDebug
                              ? 'إخفاء تفاصيل التشخيص (Developer Debug)'
                              : 'تفاصيل التشخيص (Developer Debug)',
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

                // ── تفاصيل التشخيص الشاملة (تظهر فقط عند تفعيل العلم) ──
                if (_showDeveloperDebug) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // ── قسم 1: تشخيص الموديل التفصيلي (MODEL IN-DEPTH DIAGNOSTIC) ──
                  _buildSectionHeader('MODEL IN-DEPTH DIAGNOSTICS'),
                  const SizedBox(height: 6),
                  _buildDebugCounterRow('Model File', 'assets/models/ishara_model.tflite'),
                  _buildDebugCounterRow('Model Size', '${modelPipe?.modelSizeMb.toStringAsFixed(2) ?? "107.55"} MB'),
                  _buildDebugCounterRow('Input Tensor', '${modelPipe?.inputDtype ?? "float32"} ${modelPipe?.inputShape ?? "[1, 128, 86, 2]"}'),
                  _buildDebugCounterRow('Output Tensor', '${modelPipe?.outputDtype ?? "float32"} ${modelPipe?.outputShape ?? "[1, 29, 684]"}'),
                  _buildDebugCounterRow('Total Inferences', '${modelPipe?.totalInferenceCount ?? 0}'),
                  _buildDebugCounterRow('Output Responsive', modelPipe != null && modelPipe.isResponsive ? 'YES ✅ (Changing)' : 'NO ⚠️ (Static)'),
                  if (modelPipe?.lastErrorCode != null)
                    _buildDebugCounterRow('Last Error', '${modelPipe!.lastErrorCode}: ${modelPipe.lastErrorMessage}'),
                  if (modelPipe?.lastArgmaxIds != null && modelPipe!.lastArgmaxIds!.isNotEmpty)
                    _buildDebugCounterRow('Argmax Sample (29)', '${modelPipe.lastArgmaxIds!.take(8).toList()}...'),
                  if (modelPipe?.lastTopLogits.isNotEmpty == true)
                    _buildDebugCounterRow('Top Logits Sample', modelPipe!.lastTopLogits.take(3).map((l) => 't=${l.timestep}: c=${l.topClassId}').join(', ')),

                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // ── قسم 2: تفاصيل الـ SEQUENCE BUFFER ──
                  _buildSectionHeader('SEQUENCE BUFFER DETAILS'),
                  const SizedBox(height: 6),
                  _buildCompactRow(title: 'Buffer State', value: bufferStateName, icon: bufferStateName, isGood: isBufferReady, showOnlyIconAsValue: true),
                  const SizedBox(height: 4),
                  _buildCompactRow(title: 'Latest Frame', value: latestFrameStr, icon: latestFrameStr, isGood: true, showOnlyIconAsValue: true, forceLtr: true),
                  const SizedBox(height: 4),
                  _buildCompactRow(title: 'Frame Shape', value: '[86, 2]', icon: '[86, 2]', isGood: true, showOnlyIconAsValue: true, forceLtr: true),
                  const SizedBox(height: 4),
                  _buildCompactRow(title: 'Sequence Shape', value: '[$bufferFrames, 86, 2]', icon: '[$bufferFrames, 86, 2]', isGood: isBufferReady, showOnlyIconAsValue: true, forceLtr: true),
                  const SizedBox(height: 4),
                  _buildCompactRow(title: 'Buffer NaN / Inf', value: '$bufferNanInf', icon: bufferNanInf == 0 ? '0 ✅' : '$bufferNanInf ❌', isGood: bufferNanInf == 0, showOnlyIconAsValue: true, forceLtr: true),
                  const SizedBox(height: 4),
                  _buildCompactRow(title: 'Buffer Duplicates', value: '$duplicateCount', icon: duplicateCount == 0 ? '0' : '$duplicateCount', isGood: duplicateCount == 0, showOnlyIconAsValue: true, forceLtr: true),

                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // ── قسم 3: تفاصيل الـ PREPROCESSING MODEL INPUT ──
                  _buildSectionHeader('PREPROCESSING (MODEL INPUT)'),
                  const SizedBox(height: 6),
                  _buildCompactRow(title: 'Raw detected', value: '$rawDetected / 86', icon: isRawFull ? '✅' : '❌', isGood: isRawFull, forceLtr: true),
                  const SizedBox(height: 4),
                  _buildCompactRow(title: 'Model array', value: '$modelArrayCount / 86', icon: '✅', isGood: true, forceLtr: true),
                  const SizedBox(height: 4),
                  _buildCompactRow(title: 'Normalization', value: normStatus, icon: isNormMatch ? '✅' : '❌', isGood: isNormMatch),
                  const SizedBox(height: 4),
                  _buildCompactRow(title: 'Missing/Imputed', value: '$imputedCount', icon: imputedCount == 0 ? '0' : '⚠️ $imputedCount', isGood: imputedCount == 0, showOnlyIconAsValue: true, forceLtr: true),
                  const SizedBox(height: 4),
                  _buildCompactRow(title: 'Input NaN / Inf', value: '$nanInfCount', icon: nanInfCount == 0 ? '0 ✅' : '$nanInfCount ❌', isGood: nanInfCount == 0, showOnlyIconAsValue: true, forceLtr: true),

                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // ── قسم 4: تفاصيل كشف الأجزاء الحية (LEGACY VISION DETECTIONS) ──
                  _buildSectionHeader('LEGACY VISION DETECTIONS'),
                  const SizedBox(height: 6),
                  _buildLegacyDetectionSection(context, state),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// عنوان قسم فرعي في لوحة التشخيص
  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
        letterSpacing: 0.5,
        color: Colors.blueGrey,
      ),
    );
  }

  /// سطر الواجهة المختصرة الفائقة النظافة (MODEL PIPELINE Row)
  Widget _buildCompactRow({
    required String title,
    required String value,
    required String icon,
    required bool isGood,
    bool showOnlyIconAsValue = false,
    bool forceLtr = false,
  }) {
    final Color textColor = isGood ? Colors.green.shade800 : Colors.red.shade800;

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
              _buildDebugCounterRow('Camera processed', '${state.ringBufferStatus?.totalFramesReceived ?? 0}'),
              _buildDebugCounterRow('Added to buffer', '${state.ringBufferStatus?.totalFramesAdded ?? 0}'),
              _buildDebugCounterRow('Skipped no person', '${state.ringBufferStatus?.totalFramesSkippedNoPerson ?? 0}'),
              _buildDebugCounterRow('Duplicates rejected', '${state.ringBufferStatus?.duplicateFramesRejected ?? 0}'),
              _buildDebugCounterRow('Invalid frames rejected', '${state.ringBufferStatus?.invalidFramesRejected ?? 0}'),
              _buildDebugCounterRow('Oldest Frame ID', state.ringBufferStatus?.oldestFrameSequenceId != null ? '#${state.ringBufferStatus!.oldestFrameSequenceId}' : 'None'),
              _buildDebugCounterRow('Newest Frame ID', state.ringBufferStatus?.latestFrameSequenceId != null ? '#${state.ringBufferStatus!.latestFrameSequenceId}' : 'None'),
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

  /// سطر الشخص
  Widget _buildPersonRow({required String iconEmoji, required String title, required bool isDetected}) {
    final status = isDetected ? DetectionStatus.pass : DetectionStatus.fail;
    final Color badgeBg = status == DetectionStatus.pass
        ? Colors.green.withValues(alpha: 0.15)
        : Colors.red.withValues(alpha: 0.12);
    final Color badgeBorder = status == DetectionStatus.pass
        ? Colors.green.shade600
        : Colors.red.shade400;
    final Color badgeText = status == DetectionStatus.pass
        ? Colors.green.shade800
        : Colors.red.shade800;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: status == DetectionStatus.pass
            ? Colors.green.withValues(alpha: 0.04)
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
                Text(
                  status == DetectionStatus.pass ? '✅' : '❌',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(width: 4),
                Text(
                  isDetected ? 'ظاهر' : 'غير ظاهر',
                  style: TextStyle(
                    color: badgeText,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// سطر جزء من الجسم
  Widget _buildPartRow({required String iconEmoji, required String title, required LandmarkPartStatus partStatus}) {
    final status = partStatus.status;
    final icon = partStatus.icon;

    final Color badgeBg = status == DetectionStatus.pass
        ? Colors.green.withValues(alpha: 0.15)
        : (status == DetectionStatus.partial
            ? Colors.amber.withValues(alpha: 0.15)
            : Colors.red.withValues(alpha: 0.12));

    final Color badgeBorder = status == DetectionStatus.pass
        ? Colors.green.shade600
        : (status == DetectionStatus.partial
            ? Colors.amber.shade700
            : Colors.red.shade400);

    final Color badgeText = status == DetectionStatus.pass
        ? Colors.green.shade800
        : (status == DetectionStatus.partial
            ? Colors.amber.shade900
            : Colors.red.shade800);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: status == DetectionStatus.pass
            ? Colors.green.withValues(alpha: 0.04)
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

  Widget _buildDebugCounterRow(String label, String value, {bool forceLtr = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
          ),
          Directionality(
            textDirection: forceLtr ? TextDirection.ltr : TextDirection.rtl,
            child: Text(
              value,
              textDirection: forceLtr ? TextDirection.ltr : null,
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
