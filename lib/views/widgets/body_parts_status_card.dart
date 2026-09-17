import 'package:flutter/material.dart';
import 'package:ishara/keypoints/ishara_keypoint_mapper.dart';
import 'package:ishara/models/body_parts_detection_state.dart';
import 'package:ishara/providers/vision_detection_provider.dart';
import 'package:provider/provider.dart';

/// BodyPartsStatusCard
/// بطاقة حالة التعرف المحدثة التي تعرض حالة كل جزء مع عدد النقاط الفعلي / المطلوب
/// وإجمالي نقاط الموديل الـ 86 بدقة تامة.
class BodyPartsStatusCard extends StatelessWidget {
  const BodyPartsStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VisionDetectionProvider>(
      builder: (context, visionProvider, _) {
        final state = visionProvider.state;

        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── عنوان البطاقة ومعدل الفريمات ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.visibility_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'حالة التعرف',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${state.fps.toStringAsFixed(1)} FPS',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),

                // ── 1. الشخص (Boolean فقط دون عدد نقاط) ──
                _buildPersonRow(
                  iconEmoji: '👤',
                  title: 'الشخص',
                  isDetected: state.personDetected,
                ),
                const SizedBox(height: 8),

                // ── 2. الرأس (X / 11) ──
                _buildPartRow(
                  iconEmoji: '◉',
                  title: 'الرأس',
                  partStatus: state.head,
                ),
                const SizedBox(height: 8),

                // ── 3. الوجه (X / 468) ──
                _buildPartRow(
                  iconEmoji: '🙂',
                  title: 'الوجه',
                  partStatus: state.face,
                ),
                const SizedBox(height: 8),

                // ── 4. الشفاه (X / 19) ──
                _buildPartRow(
                  iconEmoji: '👄',
                  title: 'الشفاه',
                  partStatus: state.lips,
                ),
                const SizedBox(height: 8),

                // ── 5. اليد اليمنى (X / 21) ──
                _buildPartRow(
                  iconEmoji: '🤚',
                  title: 'اليد اليمنى',
                  partStatus: state.rightHand,
                ),
                const SizedBox(height: 8),

                // ── 6. اليد اليسرى (X / 21) ──
                _buildPartRow(
                  iconEmoji: '✋',
                  title: 'اليد اليسرى',
                  partStatus: state.leftHand,
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),

                // ── ملخص نقاط الموديل 1 (Model 1 [86, 2] Verification) ──
                _buildModelVerificationSection(context, state),
              ],
            ),
          ),
        );
      },
    );
  }

  /// قسم التحقق الكامل من نقاط الموديل الـ 86
  Widget _buildModelVerificationSection(BuildContext context, VisionLandmarksState state) {
    final val = state.keypointValidation;
    final int validCount = val?.validCount ?? state.totalModelPoints;
    final bool isFull = validCount >= 86;
    final int movingCount = val?.movingPointsCount ?? 0;
    final int nanInfCount = (val?.nanCount ?? 0) + (val?.infCount ?? 0);
    final bool coordsValid = !(val?.hasInvalidNumbers ?? false);
    final bool mappingVerified = val?.isTrainingMappingVerified ?? true;

    final int rhPts = val?.validRightHandPoints ?? (state.rightHandPoints?.length ?? 0);
    final int lhPts = val?.validLeftHandPoints ?? (state.leftHandPoints?.length ?? 0);
    final int lipsPts = val?.validFaceLipPoints ?? state.modelFaceLipPoints;
    final int bodyPts = val?.validBodyHeadPoints ?? state.modelBodyHeadPoints;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // عنوان قسم الموديل
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'نقاط التدريب للموديل [86, 2]',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: mappingVerified
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                mappingVerified ? 'TRAINING ORDER VERIFIED ✅' : 'NOT VERIFIED ❌',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: mappingVerified ? Colors.green.shade800 : Colors.red.shade800,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 1. Right Hand Model Points
        _buildModelPartRow(
          title: 'Right Hand model pts',
          actual: rhPts,
          required: 21,
          isDetected: state.rightHand.detected,
        ),
        const SizedBox(height: 6),

        // 2. Left Hand Model Points
        _buildModelPartRow(
          title: 'Left Hand model pts',
          actual: lhPts,
          required: 21,
          isDetected: state.leftHand.detected,
        ),
        const SizedBox(height: 6),

        // 3. Face/Lips Model Points
        _buildModelPartRow(
          title: 'Face/Lips model pts',
          actual: lipsPts,
          required: 19,
          isDetected: state.face.detected || state.lips.detected,
        ),
        const SizedBox(height: 6),

        // 4. Body/Head Model Points
        _buildModelPartRow(
          title: 'Body/Head model pts',
          actual: bodyPts,
          required: 25,
          isDetected: state.head.detected || state.posePoints != null,
        ),
        const SizedBox(height: 12),

        const Divider(height: 1),
        const SizedBox(height: 12),

        // ── بطاقة إجمالي نقاط الموديل الـ 86 ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isFull
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFull ? Colors.green.shade400 : Colors.red.shade300,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'MODEL KEYPOINTS',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  Text(isFull ? '✅' : '❌', style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    '$validCount / 86',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: isFull ? Colors.green.shade800 : Colors.red.shade800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // صفوف الفحص الرياضي (Coordinates, NaN/Inf, Movement)
        _buildMetricRow(
          title: 'Coordinates',
          value: coordsValid ? 'VALID ✅' : 'INVALID ❌',
          color: coordsValid ? Colors.green.shade700 : Colors.red.shade700,
        ),
        const SizedBox(height: 4),

        _buildMetricRow(
          title: 'NaN / Inf',
          value: '$nanInfCount ${nanInfCount == 0 ? "✅" : "❌"}',
          color: nanInfCount == 0 ? Colors.green.shade700 : Colors.red.shade700,
        ),
        const SizedBox(height: 4),

        _buildMetricRow(
          title: 'Moving points',
          value: '$movingCount / 86',
          color: Colors.blueGrey.shade800,
        ),
        const SizedBox(height: 14),

        // ── زر Diagnostic Dump: PRINT KEYPOINT MAP ──
        ElevatedButton.icon(
          onPressed: () {
            if (state.rawKeypointFrame != null) {
              IsharaKeypointMapper.dumpKeypointMap(state.rawKeypointFrame!);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'تمت طباعة خريطة الـ 86 نقطة في Console بنجاح (Valid: ${state.rawKeypointFrame!.validCount}/86)',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('لا يوجد إطار معالم متوفر حالياً للطباعة'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
          icon: const Icon(Icons.print_rounded, size: 18),
          label: const Text(
            'PRINT KEYPOINT MAP',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  /// سطر كل جزء في فحص الموديل
  Widget _buildModelPartRow({
    required String title,
    required int actual,
    required int required,
    required bool isDetected,
  }) {
    final bool isFull = actual >= required && required > 0;
    final String icon = isFull ? '✅' : '❌';
    final Color textColor = isFull ? Colors.green.shade700 : Colors.red.shade700;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isDetected ? '✅' : '❌',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 6),
              Text(
                '$actual / $required',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: textColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// سطر مؤشر تشخيصي بسيط
  Widget _buildMetricRow({
    required String title,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// سطر حالة الشخص (Boolean فقط)
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDetected ? Colors.green.withValues(alpha: 0.03) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDetected ? Colors.green.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(iconEmoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: badgeBorder),
            ),
            child: Text(
              isDetected ? '✅ ظهر' : '❌ غير ظاهر',
              style: TextStyle(
                color: badgeText,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// سطر كل جزء مع عدد النقاط X / Y والحالات الثلاث (✅ / ⚠️ / ❌)
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: status == DetectionStatus.pass
            ? Colors.green.withValues(alpha: 0.03)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
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
              Text(iconEmoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: badgeBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(icon, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Text(
                  '${partStatus.actualPoints} / ${partStatus.requiredPoints}',
                  style: TextStyle(
                    color: badgeText,
                    fontSize: 13,
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
