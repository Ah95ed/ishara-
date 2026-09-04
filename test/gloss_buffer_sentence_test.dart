import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/controllers/gloss_controller.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/gloss_model_service.dart';

void main() {
  group('GlossController & Buffer Tests (المتطلب 3: فصل التعرف عن الترجمة)', () {
    SignPrediction makePred(String word) {
      return SignPrediction(
        label: word,
        confidence: 0.95,
        timestamp: DateTime.now(),
        secondConfidence: 0.10,
      );
    }

    test('لا يتم استدعاء نموذج الترجمة فورياً عند اعتماد الكلمة، بل تجمع في الـ Gloss Buffer', () {
      final glossService = GlossModelService();
      final controller = GlossController(
        glossService,
        sentencePauseDuration: const Duration(milliseconds: 2000),
        maxBufferWords: 7,
      );

      // 1. إضافة كلمة "أنا"
      controller.onStableSign(makePred('أنا'));

      expect(controller.bufferedGlossTokens, equals(['أنا']));
      expect(controller.hasSentence, isFalse, reason: 'يجب ألا يتم استدعاء الترجمة فورياً للكلمة الأولى');
      expect(controller.displayText, contains('أنا'));

      // 2. إضافة كلمة "أحبك"
      controller.onStableSign(makePred('أحبك'));

      expect(controller.bufferedGlossTokens, equals(['أنا', 'أحبك']));
      expect(controller.hasSentence, isFalse);
      expect(controller.displayText, equals('أنا ... أحبك'));

      controller.dispose();
    });

    test('اكتمال الجملة وترجمتها عند بلوغ الحد الأقصى للكلمات في الـ Buffer (7 كلمات)', () async {
      final glossService = GlossModelService();
      final controller = GlossController(
        glossService,
        sentencePauseDuration: const Duration(seconds: 10), // مهلة طويلة لن تنتهي
        maxBufferWords: 3, // نختبر حد 3 كلمات
      );

      controller.onStableSign(makePred('أنا'));
      controller.onStableSign(makePred('ذهاب'));
      expect(controller.hasSentence, isFalse);

      // إضافة الكلمة الثالثة (بلوغ الحد الأقصى)
      controller.onStableSign(makePred('سوق'));

      // يجب أن يتم إطلاق الترجمة وتحديث الجملة
      await Future.delayed(const Duration(milliseconds: 200));

      expect(controller.hasSentence, isTrue, reason: 'الوصول للحد الأقصى يجب أن يترجم الجملة تلقائياً');
      expect(controller.displayText, contains('السوق'));

      controller.dispose();
    });

    test('زر الترجمة اليدوي (ترجم الآن) يطلق الترجمة فورياً', () async {
      final glossService = GlossModelService();
      final controller = GlossController(
        glossService,
        sentencePauseDuration: const Duration(seconds: 30),
        maxBufferWords: 10,
      );

      controller.onStableSign(makePred('ماء'));
      expect(controller.hasSentence, isFalse);

      // ضغط زر ترجم الآن
      controller.triggerManualTranslation();

      await Future.delayed(const Duration(milliseconds: 200));

      expect(controller.hasSentence, isTrue);
      expect(controller.displayText, contains('الماء'));

      controller.dispose();
    });

    test('سكون نهاية الجملة يترجم الكلمات المجمعة بعد انقضاء المهلة', () async {
      final glossService = GlossModelService();
      final controller = GlossController(
        glossService,
        sentencePauseDuration: const Duration(milliseconds: 100), // مهلة سريعة للاختبار
        maxBufferWords: 10,
      );

      controller.onStableSign(makePred('شكراً'));
      expect(controller.hasSentence, isFalse);

      // انتظار سكون نهاية الجملة
      await Future.delayed(const Duration(milliseconds: 300));

      expect(controller.hasSentence, isTrue);
      expect(controller.displayText, contains('شكراً'));

      controller.dispose();
    });
  });
}
