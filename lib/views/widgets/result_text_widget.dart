import 'package:flutter/material.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/views/theme/app_colors.dart';

class ResultTextWidget extends StatelessWidget {
  final String text;
  final bool isLoading;

  const ResultTextWidget({super.key, required this.text, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    final displayText = text.isEmpty
        ? AppConstants.noPredictionMessage
        : text;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayText,
            style: TextStyle(
              fontSize: text.isEmpty ? 16 : 22,
              fontWeight: text.isEmpty ? FontWeight.w500 : FontWeight.w600,
              color: text.isEmpty ? AppColors.outline : AppColors.onSurface,
              height: 1.5,
            ),
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
          ),
          if (isLoading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.primary,
            ),
          ],
        ],
      ),
    );
  }
}
