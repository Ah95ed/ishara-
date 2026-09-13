import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/motion_analyzer.dart';
import 'package:ishara/services/sign_rejection_layer.dart';

void main() {
  group('SignRejectionLayer Tests (المتطلب 1: طبقة رفض القرار الضعيف)', () {
    const rejectionLayer = SignRejectionLayer(
      minConfidence: 0.60,
      confidenceMargin: 0.15,
      minMotionEnergy: 0.018,
      minVelocity: 0.025,
    );

    SignPrediction makePred({
      required String label,
      required double confidence,
      String? secondLabel,
      double secondConfidence = 0.0,
      double? margin,
    }) {
      return SignPrediction(
        label: label,
        confidence: confidence,
        timestamp: DateTime.now(),
        secondLabel: secondLabel,
        secondConfidence: secondConfidence,
        confidenceMargin: margin ?? (confidence - secondConfidence),
      );
    }

    MotionFeatures activeMotion({double energy = 0.035, double vel = 0.040}) {
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

    test('Motion Energy: سكون اليد يُصنف IDLE / NO_SIGN قطعياً مهما كانت ثقة النموذج', () {
      // حالة يد ساكنة والموديل يخرج "السلام" بثقة 0.99
      final pred = makePred(label: 'السلام', confidence: 0.99, secondConfidence: 0.01);
      final eval = rejectionLayer.evaluate(
        prediction: pred,
        motion: idleMotion(), // سكون تام
      );

      expect(eval.isAccepted, isFalse);
      expect(eval.isIdle, isTrue);
      expect(eval.reason, equals(RejectionReason.idle));
      expect(eval.description, contains('سكون اليد'));
    });

    test('Absolute Confidence: ثقة أقل من 0.60 تُرفض', () {
      final pred = makePred(label: 'ماء', confidence: 0.52, secondConfidence: 0.10);
      final eval = rejectionLayer.evaluate(
        prediction: pred,
        motion: activeMotion(),
      );

      expect(eval.isAccepted, isFalse);
      expect(eval.reason, equals(RejectionReason.lowConfidence));
      expect(eval.description, contains('ثقة منخفضة'));
    });

    test('Confidence Margin: إذا كان الفرق بين Top-1 و Top-2 أقل من 0.15 يُرفض القرار لتردد النموذج', () {
      // Top-1 = 0.70 ("طعام")، Top-2 = 0.60 ("ماء") -> Margin = 0.10 (< 0.15)
      final pred = makePred(
        label: 'طعام',
        confidence: 0.70,
        secondLabel: 'ماء',
        secondConfidence: 0.60,
      );

      final eval = rejectionLayer.evaluate(
        prediction: pred,
        motion: activeMotion(),
      );

      expect(eval.isAccepted, isFalse);
      expect(eval.reason, equals(RejectionReason.undecidedMargin));
      expect(eval.description, contains('قرار غير محسوم'));
    });

    test('Word Only: الأحرف المنفردة تُرفض قطعياً', () {
      final pred = makePred(label: 'أ', confidence: 0.95, secondConfidence: 0.05);
      final eval = rejectionLayer.evaluate(
        prediction: pred,
        motion: activeMotion(),
      );

      expect(eval.isAccepted, isFalse);
      expect(eval.reason, equals(RejectionReason.invalidWord));
    });

    test('قبول المرشح إذا استوفى كافة شروط الثقة والحركة والفارق', () {
      // Top-1 = 0.88 ("أحبك")، Top-2 = 0.20 ("السلام") -> Margin = 0.68 (> 0.15) مع حركة نشطة
      final pred = makePred(
        label: 'أحبك',
        confidence: 0.88,
        secondLabel: 'السلام',
        secondConfidence: 0.20,
      );

      final eval = rejectionLayer.evaluate(
        prediction: pred,
        motion: activeMotion(),
      );

      expect(eval.isAccepted, isTrue);
      expect(eval.isIdle, isFalse);
      expect(eval.reason, equals(RejectionReason.none));
      expect(eval.prediction!.label, equals('أحبك'));
    });
  });
}
