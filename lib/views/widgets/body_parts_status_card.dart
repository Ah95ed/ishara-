import 'package:flutter/material.dart';
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

                // ── ملخص نقاط الموديل (Model Point Mapping) ──
                _buildModelSummaryRow(
                  title: 'Face/Lips Model Points',
                  actual: state.modelFaceLipPoints,
                  required: 19,
                ),
                const SizedBox(height: 6),

                _buildModelSummaryRow(
                  title: 'Body/Head Model Points',
                  actual: state.modelBodyHeadPoints,
                  required: 25,
                ),
                const SizedBox(height: 10),

                // ── إجمالي نقاط الموديل الـ 86 ──
                _buildTotalPointsCard(state),
              ],
            ),
          ),
        );
      },
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

  /// سطر ملخص نقاط أجزاء الموديل
  Widget _buildModelSummaryRow({
    required String title,
    required int actual,
    required int required,
  }) {
    final bool isFull = actual >= required && required > 0;
    final bool isPartial = actual > 0 && actual < required;

    final String icon = isFull ? '✅' : (isPartial ? '⚠️' : '❌');
    final Color textColor = isFull
        ? Colors.green.shade700
        : (isPartial ? Colors.amber.shade800 : Colors.red.shade700);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 12)),
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

  /// بطاقة إجمالي نقاط الموديل الـ 86
  Widget _buildTotalPointsCard(VisionLandmarksState state) {
    final bool isFull = state.totalModelPoints >= 86;
    final String icon = isFull ? '✅' : '❌';
    final Color cardColor = isFull
        ? Colors.green.withValues(alpha: 0.1)
        : Colors.red.withValues(alpha: 0.08);

    final Color borderColor = isFull ? Colors.green.shade400 : Colors.red.shade300;
    final Color textColor = isFull ? Colors.green.shade800 : Colors.red.shade800;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                'النقاط المطلوبة للموديل',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                '${state.totalModelPoints} / 86',
                style: TextStyle(
                  fontSize: 16,
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
}
