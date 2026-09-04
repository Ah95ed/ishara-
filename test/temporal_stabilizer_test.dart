import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/temporal_stabilizer.dart';

void main() {
  group('TemporalStabilizer Tests (المتطلبات 2، 5، 6، 7، 9، 11، 12)', () {
    SignPrediction pred(String label, double confidence) {
      return SignPrediction(
        label: label,
        confidence: confidence,
        timestamp: DateTime.now(),
      );
    }

    test('Duplicate Suppression: منع تكرار نفس الكلمة (أحبك أحبك) طالما الإشارة مستمرة', () {
      final stabilizer = TemporalStabilizer();
      final emittedWords = <String>[];

      stabilizer.onStableSign = (p) {
        emittedWords.add(p.label);
      };

      // إرسال كلمة "أحبك" بثقة عالية عبر عدة إطارات متتالية
      for (int i = 0; i < 15; i++) {
        stabilizer.processPrediction(pred('أحبك', 0.95));
      }

      // يجب أن تُعتمد مرة واحدة فقط!
      expect(emittedWords.length, equals(1));
      expect(emittedWords.first, equals('أحبك'));
    });

    test('CTC-like Collapse: تتكرر الكلمة فقط بعد المرور بحالة BLANK حقيقية', () {
      final stabilizer = TemporalStabilizer();
      final emittedWords = <String>[];

      stabilizer.onStableSign = (p) {
        emittedWords.add(p.label);
      };

      // 1. كلمة "ماء"
      for (int i = 0; i < 8; i++) {
        stabilizer.processPrediction(pred('ماء', 0.94));
      }
      expect(emittedWords.length, equals(1));
      expect(emittedWords.last, equals('ماء'));

      // 2. حالة BLANK (انقطاع اليد أو وضع محايد)
      for (int i = 0; i < 5; i++) {
        stabilizer.processPrediction(null);
      }

      // 3. كلمة "ماء" من جديد بعد الـ BLANK
      for (int i = 0; i < 8; i++) {
        stabilizer.processPrediction(pred('ماء', 0.94));
      }
      expect(emittedWords.length, equals(2));
      expect(emittedWords, equals(['ماء', 'ماء']));
    });

    test('Early Exit: ثبات الكلمة بثقة فائقة ينهي التحليل مبكراً دون استهلاك فريمات إضافية', () {
      final stabilizer = TemporalStabilizer(
        minWindowSize: 6,
        earlyExitConfidence: 0.88,
      );

      SignPrediction? emitted;
      stabilizer.onStableSign = (p) {
        emitted = p;
      };

      // إرسال 6 إطارات متطابقة بثقة 0.95
      for (int i = 0; i < 6; i++) {
        stabilizer.processPrediction(pred('السلام', 0.95));
      }

      expect(emitted, isNotNull);
      expect(emitted!.label, equals('السلام'));
      expect(stabilizer.state, equals(SignStabilityState.stable));
    });

    test('Confidence Gate: الثقة المنخفضة تبقي الحالة Detecting ولا تصدر تخميناً خاطئاً', () {
      final stabilizer = TemporalStabilizer(minConfidenceThreshold: 0.70);
      SignPrediction? emitted;

      stabilizer.onStableSign = (p) {
        emitted = p;
      };

      for (int i = 0; i < 10; i++) {
        stabilizer.processPrediction(pred('طعام', 0.50));
      }

      expect(emitted, isNull);
      expect(stabilizer.state, equals(SignStabilityState.detecting));
    });

    test('Word Only Filter: استبعاد أي حرف منفرد يمرر للمثبت الزمني', () {
      final stabilizer = TemporalStabilizer();
      SignPrediction? emitted;

      stabilizer.onStableSign = (p) {
        emitted = p;
      };

      // إرسال حرف 'أ' متكرراً
      for (int i = 0; i < 10; i++) {
        stabilizer.processPrediction(pred('أ', 0.95));
      }

      expect(emitted, isNull, reason: 'الحرف المنفرد يجب ألا يتم اعتماده أبداً');
    });
  });
}
