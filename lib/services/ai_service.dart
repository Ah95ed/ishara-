import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ishara/models/sign_prediction_model.dart';

abstract class AIService {
  Future<String?> translateSequence(List<SignPrediction> sequence);
  Future<void> dispose();
}

class GeminiAIService implements AIService {
  final String apiKey;
  final String model;
  final String endpoint;

  GeminiAIService({
    required this.apiKey,
    this.model = 'gemini-2.0-flash',
    this.endpoint = 'https://generativelanguage.googleapis.com/v1beta/models',
  });

  @override
  Future<String?> translateSequence(List<SignPrediction> sequence) async {
    if (sequence.isEmpty) return null;

    final words = sequence.map((s) => s.label.trim()).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return null;

    // إن لم يتوفر مفتاح API نستخدم المحرك المحلي المتقدم مباشرة
    if (apiKey.isEmpty || apiKey == 'YOUR_GEMINI_API_KEY') {
      return LocalArabicGrammarEngine.reconstruct(words);
    }

    final rawTokens = words.join(' ');
    final prompt = '''
أنت خبير لغة الإشارة العربية الفصحى. مهمتك تحويل تسلسل الإشارات المتقطعة إلى جملة عربية مفيدة وطبيعية ومترابطة نحوياً وقواعدياً.
قواعد الإخراج:
1. اكتب الجملة العربية المكتملة فقط بدون مقدمات أو شروحات.
2. نسق الأفعال والضمائر وحروف الجر بدقة.

أمثلة:
- التسلسل: أنا أريد ذهاب سوق -> الجملة: أنا أريد الذهاب إلى السوق.
- التسلسل: أنا ماء -> الجملة: أنا أريد أن أشرب ماء.
- التسلسل: أنت مساعدة أنا -> الجملة: هل يمكنك مساعدتي من فضلك؟
- التسلسل: أنا أريد ذهاب مستشفى -> الجملة: أنا أريد الذهاب إلى المستشفى.
- التسلسل: شكرا أنت -> الجملة: شكراً جزيلاً لك.
- التسلسل: أنا طعام -> الجملة: أنا جائع وأريد طعاماً.

التسلسل: $rawTokens
الجملة:''';

    try {
      final url = '$endpoint/$model:generateContent?key=$apiKey';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.1,
            'maxOutputTokens': 80,
          },
        }),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'] as Map?;
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text'] as String?;
            if (text != null && text.trim().isNotEmpty) {
              return text.trim().replaceAll(RegExp(r'^["«]+|["»]+$'), '');
            }
          }
        }
      }
    } catch (e) {
      // Fallback on network/API failure
    }

    return LocalArabicGrammarEngine.reconstruct(words);
  }

  @override
  Future<void> dispose() async {}
}

class FallbackAIService extends ChangeNotifier implements AIService {
  @override
  Future<String?> translateSequence(List<SignPrediction> sequence) async {
    final words = sequence.map((s) => s.label.trim()).where((w) => w.isNotEmpty).toList();
    return LocalArabicGrammarEngine.reconstruct(words);
  }

  @override
  Future<void> dispose() async {
    super.dispose();
  }
}

/// محرك محلي ذكي لصياغة الجمل العربية وفق قواعد لغة الإشارة بدون إنترنت
class LocalArabicGrammarEngine {
  static String reconstruct(List<String> words) {
    if (words.isEmpty) return '';

    if (words.length == 1) {
      final single = words.first;
      switch (single) {
        case 'شكراً':
          return 'شكراً جزيلاً لك.';
        case 'مرحبا':
          return 'مرحباً، أهلاً وسهلاً.';
        case 'مساعدة':
          return 'أحتاج إلى المساعدة من فضلك.';
        case 'ماء':
          return 'أريد ماءً للشرب.';
        case 'طعام':
          return 'أريد طعاماً للأكل.';
        case 'أحبك':
          return 'أنا أحبك كثيراً.';
        default:
          return '$single.';
      }
    }
    if (words.contains('أنا') && words.contains('أريد') && words.contains('الذهاب') && (words.contains('السوق') || words.contains('سوق'))) {
      return 'أنا أريد الذهاب إلى السوق.';
    }
    if (words.contains('أنا') && (words.contains('الذهاب') || words.contains('أريد')) && words.contains('البيت')) {
      return 'أنا أريد الذهاب إلى المنزل.';
    }
    if (words.contains('أنا') && (words.contains('الذهاب') || words.contains('أريد')) && words.contains('مستشفى')) {
      return 'أنا بحاجة للذهاب إلى المستشفى فوراً.';
    }
    if (words.contains('أنت') && words.contains('مساعدة') && words.contains('أنا')) {
      return 'هل يمكنك مساعدتي من فضلك؟';
    }
    if (words.contains('أنا') && words.contains('ماء')) {
      return 'أنا أريد أن أشرب ماء.';
    }
    if (words.contains('أنا') && words.contains('طعام')) {
      return 'أنا أريد تناول بعض الطعام.';
    }
    if (words.contains('شكراً') && (words.contains('أنت') || words.contains('كثيراً'))) {
      return 'شكراً جزيلاً لك على مساعدتك.';
    }
    if (words.contains('أنا') && words.contains('أحبك')) {
      return 'أنا أحبك كثيراً.';
    }

    // 2. صياغة قواعدية قياسية (Syntactic connector)
    final buffer = StringBuffer();
    for (int i = 0; i < words.length; i++) {
      final current = words[i];
      final next = (i + 1 < words.length) ? words[i + 1] : null;

      buffer.write(current);

      if (current == 'الذهاب' && next != null && next != 'إلى' && (next == 'السوق' || next == 'البيت' || next == 'مستشفى')) {
        buffer.write(' إلى ');
      } else if (i < words.length - 1) {
        buffer.write(' ');
      }
    }

    final result = buffer.toString().trim();
    if (!result.endsWith('.') && !result.endsWith('؟') && !result.endsWith('!')) {
      return '$result.';
    }
    return result;
  }
}
