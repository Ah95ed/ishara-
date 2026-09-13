import 'package:flutter/material.dart';
import 'package:ishara/controllers/sign_controller.dart';
import 'package:provider/provider.dart';

class SignDictionarySheet extends StatelessWidget {
  const SignDictionarySheet({super.key});

  static const List<Map<String, String>> signsList = [
    {
      'sign': 'أنا',
      'desc': 'رفع إصبع السبابة فقط للأعلى وبقية الأصابع مقفولة',
      'icon': '☝️',
    },
    {
      'sign': 'الذهاب',
      'desc': 'رفع إصبعين متباعدين (علامة V)',
      'icon': '✌️',
    },
    {
      'sign': 'مستشفى',
      'desc': 'رفع إصبعين متلاصقين (سبابة ووسطى متلاصقتان)',
      'icon': '🏥',
    },
    {
      'sign': 'ماء',
      'desc': 'رفع 3 أصابع (سبابة ووسطى وبنصر علامة W)',
      'icon': '💧',
    },
    {
      'sign': 'أحبك',
      'desc': 'رفع الإبهام والسبابة والخنصر (علامة ILY)',
      'icon': '🤟',
    },
    {
      'sign': 'نعم',
      'desc': 'رفع الإبهام فقط للأعلى',
      'icon': '👍',
    },
    {
      'sign': 'أريد',
      'desc': 'رفع 4 أصابع ممدودة والإبهام مقفول',
      'icon': '🤲',
    },
    {
      'sign': 'لا',
      'desc': 'قبضة يد مقفولة بالكامل بدون أي أصابع',
      'icon': '✊',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.menu_book_rounded, color: Colors.blueAccent),
                  SizedBox(width: 8),
                  Text(
                    'الإشارات المعتمدة (8 إشارات)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: signsList.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = signsList[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(item['icon'] ?? '✋', style: const TextStyle(fontSize: 18)),
                  ),
                  title: Text(
                    item['sign'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  subtitle: Text(
                    item['desc'] ?? '',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                    tooltip: 'إضافة للتسلسل',
                    onPressed: () {
                      context.read<SignProvider>().addWord(item['sign']!);
                      Navigator.pop(context);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
