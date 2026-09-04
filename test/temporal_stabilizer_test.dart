import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/motion_analyzer.dart';
import 'package:ishara/services/temporal_stabilizer.dart';

void main() {
  group('TemporalStabilizer State Machine Tests (المتطلب 2: آلة الحالة الزمنية)', () {
    SignPrediction pred(String label, double confidence, {double secondConfidence = 0.10}) {
      return SignPrediction(
        label: label,
        confidence: confidence,
        timestamp: DateTime.now(),
        secondConfidence: secondConfidence,
        confidenceMargin: confidence - secondConfidence,
      );
    }

    MotionFeatures activeMotion({double vel = 0.040, double energy = 0.030}) {
      return MotionFeatures(
        averageVelocity: vel,
        wristVelocity: vel,
        directionX: 0.0,
        directionY: 0.0,
        directionZ: 0.0,
        motionEnergy: energy,
        angularVelocity: 0.0,
        distanceRate: 0.0,
        isHandStatic: false,
        isSignBoundary: false,
      );
    }

    MotionFeatures idleMotion() {
      return MotionFeatures.staticInitial();
    }

    test('Duplicate Suppression: منع تكرار نفس الكلمة (أحبك أحبك) طالما الإشارة مستمرة', () {
      final stabilizer = TemporalStabilizer();
      final emittedWords = <String>[];

      stabilizer.onStableSign = (p) {
        emittedWords.add(p.label);
      };

      // إرسال كلمة "أحبك" بثقة عالية عبر عدة إطارات متتالية مع حركة نشطة
      for (int i = 0; i < 15; i++) {
        stabilizer.processPrediction(pred('أحبك', 0.95), motion: activeMotion());
      }

      // يجب أن تُعتمد مرة واحدة فقط وتدخل فترة التبريد!
      expect(emittedWords.length, equals(1));
      expect(emittedWords.first, equals('أحبك'));
      expect(stabilizer.state, equals(SignStabilityState.cooldown));
    });

    test('CTC-like Collapse: تتكرر الكلمة فقط بعد المرور بحالة سكون أو فراغ حقيقية (IDLE)', () {
      final stabilizer = TemporalStabilizer();
      final emittedWords = <String>[];

      stabilizer.onStableSign = (p) {
        emittedWords.add(p.label);
      };

      // 1. كلمة "ماء"
      for (int i = 0; i < 8; i++) {
        stabilizer.processPrediction(pred('ماء', 0.94), motion: activeMotion());
      }
      expect(emittedWords.length, equals(1));
      expect(emittedWords.last, equals('ماء'));

      // 2. حالة سكون تام IDLE (انقطاع اليد أو وضع محايد)
      for (int i = 0; i < 5; i++) {
        stabilizer.processPrediction(null, motion: idleMotion());
      }
      expect(stabilizer.state, equals(SignStabilityState.idle));

      // 3. كلمة "ماء" من جديد بحركة نشطة بعد السكون
      for (int i = 0; i < 8; i++) {
        stabilizer.processPrediction(pred('ماء', 0.94), motion: activeMotion());
      }
      expect(emittedWords.length, equals(2));
      expect(emittedWords, equals(['ماء', 'ماء']));
    });

    test('Early Exit: ثبات الكلمة بثقة فائقة ينهي التحليل مبكراً دون استهلاك فريمات إضافية', () {
      final stabilizer = TemporalStabilizer(
        earlyExitConfidence: 0.85,
      );

      SignPrediction? emitted;
      stabilizer.onStableSign = (p) {
        emitted = p;
      };

      // إرسال 6 إطارات متطابقة بثقة 0.95
      for (int i = 0; i < 6; i++) {
        stabilizer.processPrediction(pred('السلام', 0.95), motion: activeMotion());
      }

      expect(emitted, isNotNull);
      expect(emitted!.label, equals('السلام'));
      // بعد الاعتماد مباشرة تنتقل لحالة التبريد (COOLDOWN)
      expect(stabilizer.state.isCooldownState, isTrue);
    });

    test('كسر الـ Cooldown بقفزة حركة واضحة (Motion Spike)', () {
      final stabilizer = TemporalStabilizer(cooldownFrames: 20);
      final emittedWords = <String>[];

      stabilizer.onStableSign = (p) {
        emittedWords.add(p.label);
      };

      // 1. اعتماد كلمة "أنا" والدخول في التبريد
      for (int i = 0; i < 6; i++) {
        stabilizer.processPrediction(pred('أنا', 0.95), motion: activeMotion());
      }
      expect(stabilizer.state, equals(SignStabilityState.cooldown));
      expect(emittedWords, equals(['أنا']));

      // 2. قفزة حركة واضحة (Motion Spike: سرعة 0.060 > 0.045) تكسر التبريد فوراً
      stabilizer.processPrediction(
        pred('أحبك', 0.95),
        motion: activeMotion(vel: 0.060, energy: 0.050),
      );

      // يجب أن تنكسر حالة التبريد وتنتقل إلى SIGNING لبدء استقبال الإشارة التالية
      expect(stabilizer.state, equals(SignStabilityState.signing));
    });

    test('Confidence Gate: الثقة المنخفضة تبقي الحالة Detecting/Idle ولا تصدر تخميناً خاطئاً', () {
      final stabilizer = TemporalStabilizer(minConfidenceThreshold: 0.70);
      SignPrediction? emitted;

      stabilizer.onStableSign = (p) {
        emitted = p;
      };

      for (int i = 0; i < 10; i++) {
        stabilizer.processPrediction(pred('طعام', 0.50), motion: activeMotion());
      }

      expect(emitted, isNull);
      expect(stabilizer.state.isSigningState, isTrue); // تجمع إطارات ولكن ترفض القرار لضعف الثقة
    });

    test('Word Only Filter: استبعاد أي حرف منفرد يمرر للمثبت الزمني', () {
      final stabilizer = TemporalStabilizer();
      SignPrediction? emitted;

      stabilizer.onStableSign = (p) {
        emitted = p;
      };

      // إرسال حرف 'أ' متكرراً
      for (int i = 0; i < 10; i++) {
        stabilizer.processPrediction(pred('أ', 0.95), motion: activeMotion());
      }

      expect(emitted, isNull, reason: 'الحرف المنفرد يجب ألا يتم اعتماده أبداً');
    });
  });
}
