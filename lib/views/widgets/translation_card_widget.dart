import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ishara/controllers/translation_controller.dart';
import 'package:provider/provider.dart';

class TranslationCardWidget extends StatelessWidget {
  final VoidCallback onTranslate;

  const TranslationCardWidget({
    super.key,
    required this.onTranslate,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<TranslationController>(
      builder: (context, translationCtrl, _) {
        final text = translationCtrl.translatedText;
        final isProcessing = translationCtrl.isProcessing;
        final status = translationCtrl.status;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                Theme.of(context).colorScheme.secondary.withValues(alpha: 0.04),
              ],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.auto_awesome,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'الجملة المترجمة:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: isProcessing
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text(
                                'جارٍ صياغة الجملة بالذكاء الاصطناعي...',
                                style: TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        key: ValueKey(text),
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 70),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            text.isNotEmpty ? text : 'ستظهر هنا الجملة المكتملة والمفهومة بعد الترجمة...',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: text.isNotEmpty ? 20 : 14,
                              fontWeight: text.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                              color: text.isNotEmpty
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: isProcessing ? null : onTranslate,
                      icon: const Icon(Icons.translate_rounded),
                      label: const Text('ترجمة وصياغة الجملة'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  if (text.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم نسخ الجملة إلى الحافظة'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      tooltip: 'نسخ النص',
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
