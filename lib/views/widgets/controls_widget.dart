import 'package:flutter/material.dart';

class ControlsWidget extends StatelessWidget {
  final VoidCallback? onSpeak;
  final VoidCallback? onDelete;
  final VoidCallback? onClear;
  final bool isSpeaking;
  final bool autoSpeak;
  final VoidCallback? onToggleAutoSpeak;

  const ControlsWidget({
    super.key,
    this.onSpeak,
    this.onDelete,
    this.onClear,
    this.isSpeaking = false,
    this.autoSpeak = true,
    this.onToggleAutoSpeak,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onSpeak,
              icon: Icon(isSpeaking ? Icons.stop_circle : Icons.volume_up_rounded, size: 20),
              label: Text(isSpeaking ? 'إيقاف' : 'نطق الجملة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isSpeaking ? Colors.orange : Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            onPressed: onDelete,
            icon: const Icon(Icons.backspace_outlined, size: 18),
            tooltip: 'حذف آخر كلمة',
          ),
          const SizedBox(width: 4),
          IconButton.outlined(
            onPressed: onClear,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            tooltip: 'مسح التسلسل',
          ),
          const SizedBox(width: 4),
          IconButton.filledTonal(
            onPressed: onToggleAutoSpeak,
            icon: Icon(
              autoSpeak ? Icons.record_voice_over_rounded : Icons.voice_over_off_rounded,
              size: 18,
              color: autoSpeak ? Colors.green : Colors.grey,
            ),
            tooltip: autoSpeak ? 'النطق التلقائي: مفعل' : 'النطق التلقائي: معطل',
          ),
        ],
      ),
    );
  }
}
