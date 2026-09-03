import 'package:flutter/material.dart';
import 'package:ishara/theme/app_colors.dart';

class ConfidenceWidget extends StatelessWidget {
  final double confidence;
  final String? label;

  const ConfidenceWidget({super.key, required this.confidence, this.label});

  @override
  Widget build(BuildContext context) {
    final percent = (confidence * 100).toInt();
    final color = confidence >= 0.8
        ? AppColors.success
        : confidence >= 0.5
            ? AppColors.warning
            : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$percent%',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (label != null && label!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              'الإشارة اللحظية: $label',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
