import 'package:flutter/material.dart';
import 'package:ishara/providers/vision_detection_provider.dart';
import 'package:provider/provider.dart';

/// BodyPartsStatusCard
/// بطاقة حالة التعرف البسيطة والمباشرة المطلوبة أسفل الكاميرا
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
                // ── عنوان البطاقة ──
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
                const SizedBox(height: 16),

                // ── الحالات الـ 6 المحددة ──
                _buildStatusRow(
                  iconEmoji: '👤',
                  title: 'الشخص',
                  isDetected: state.person,
                  detectedText: '✅ ظهر',
                  notDetectedText: '❌ غير ظاهر',
                ),
                const SizedBox(height: 10),

                _buildStatusRow(
                  iconEmoji: '◉',
                  title: 'الرأس',
                  isDetected: state.head,
                  detectedText: '✅ ظهر',
                  notDetectedText: '❌ غير ظاهر',
                ),
                const SizedBox(height: 10),

                _buildStatusRow(
                  iconEmoji: '🙂',
                  title: 'الوجه',
                  isDetected: state.face,
                  detectedText: '✅ ظهر',
                  notDetectedText: '❌ غير ظاهر',
                ),
                const SizedBox(height: 10),

                _buildStatusRow(
                  iconEmoji: '👄',
                  title: 'الشفاه',
                  isDetected: state.lips,
                  detectedText: '✅ ظهرت',
                  notDetectedText: '❌ غير ظاهرة',
                ),
                const SizedBox(height: 10),

                _buildStatusRow(
                  iconEmoji: '🤚',
                  title: 'اليد اليمنى',
                  isDetected: state.rightHand,
                  detectedText: '✅ ظهرت',
                  notDetectedText: '❌ غير ظاهرة',
                ),
                const SizedBox(height: 10),

                _buildStatusRow(
                  iconEmoji: '✋',
                  title: 'اليد اليسرى',
                  isDetected: state.leftHand,
                  detectedText: '✅ ظهرت',
                  notDetectedText: '❌ غير ظاهرة',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusRow({
    required String iconEmoji,
    required String title,
    required bool isDetected,
    required String detectedText,
    required String notDetectedText,
  }) {
    final Color badgeBgColor = isDetected
        ? Colors.green.withValues(alpha: 0.12)
        : Colors.red.withValues(alpha: 0.08);

    final Color badgeTextColor = isDetected ? Colors.green.shade700 : Colors.red.shade700;
    final Color badgeBorderColor = isDetected
        ? Colors.green.withValues(alpha: 0.4)
        : Colors.red.withValues(alpha: 0.25);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDetected
            ? Colors.green.withValues(alpha: 0.04)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
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
              Text(
                iconEmoji,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: badgeBgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: badgeBorderColor),
            ),
            child: Text(
              isDetected ? detectedText : notDetectedText,
              style: TextStyle(
                color: badgeTextColor,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
