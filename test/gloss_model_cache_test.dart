import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/services/gloss_model_service.dart';

void main() {
  group('GlossModelService & Cache Tests (المتطلبان 15 و 16)', () {
    test('Cache Hit: استرجاع الجملة المترجمة فورياً عند تكرار نفس التسلسل دون إعادة الاستنتاج', () async {
      final service = GlossModelService();

      // 1. أول ترجمة للتسلسل
      final result1 = await service.translateGloss('أنا ذهاب سوق');
      expect(result1, isNotNull);
      expect(result1!.arabicText, contains('السوق'));
      expect(result1.isFromCache, isFalse);

      // 2. نفس التسلسل مجدداً ➔ Cache Hit فوري بزمن 0ms
      final result2 = await service.translateGloss('أنا ذهاب سوق');
      expect(result2, isNotNull);
      expect(result2!.arabicText, equals(result1.arabicText));
      expect(result2.isFromCache, isTrue, reason: 'يجب استرجاع النتيجة من الـ Cache لتوفير البطارية');
      expect(result2.totalLatencyMs, equals(0));
    });

    test('ترجمة جملة واحدة بسيطة مخزنة', () async {
      final service = GlossModelService();

      final result = await service.translateGloss('ماء');
      expect(result, isNotNull);
      expect(result!.arabicText, contains('الماء'));
    });
  });
}
