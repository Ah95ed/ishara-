import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/models/landmarks_model.dart';
import 'package:ishara/services/motion_analyzer.dart';

void main() {
  group('MotionAnalyzer & Motion Gate Tests (المتطلبات 1 و 4 و 8)', () {
    HandLandmarks createLandmarks({double offsetX = 0.0, double offsetY = 0.0}) {
      final list = <HandLandmark>[];
      for (int i = 0; i < 21; i++) {
        list.add(HandLandmark(
          index: i,
          x: 0.5 + offsetX + (i * 0.01),
          y: 0.5 + offsetY + (i * 0.01),
          z: 0.0,
        ));
      }
      return HandLandmarks(
        landmarks: list,
        handedness: Handedness.right,
        confidence: 0.95,
      );
    }

    test('Motion Gate: اليد الثابتة (بدون حركة) تعيد isHandStatic = true', () {
      final analyzer = MotionAnalyzer(motionGateThreshold: 0.015);

      final frame1 = createLandmarks(offsetX: 0.0, offsetY: 0.0);
      final res1 = analyzer.analyze(frame1);
      expect(res1.isHandStatic, isTrue);

      // إزاحة صغيرة جداً (تذبذب مستشعر) أقل من 0.015
      final frame2 = createLandmarks(offsetX: 0.0005, offsetY: 0.0005);
      final res2 = analyzer.analyze(frame2);
      expect(res2.isHandStatic, isTrue, reason: 'التذبذب البسيط يجب أن يصنف كيَد ثابتة لتوفير المعالج');
    });

    test('Motion Features: حركة اليد الفعلية تعيد isHandStatic = false وسرعة وطاقة حركية موجبة', () {
      final analyzer = MotionAnalyzer(motionGateThreshold: 0.015);

      final frame1 = createLandmarks(offsetX: 0.0, offsetY: 0.0);
      analyzer.analyze(frame1);

      // إزاحة ملحوظة (حركة يد حقيقية)
      final frame2 = createLandmarks(offsetX: 0.08, offsetY: 0.05);
      final res2 = analyzer.analyze(frame2);

      expect(res2.isHandStatic, isFalse, reason: 'الحركة الواضحة يجب أن تفعل بوابة الحركة');
      expect(res2.averageVelocity, greaterThan(0.0));
      expect(res2.motionEnergy, greaterThan(0.0));
    });

    test('Sign Boundary Detection: الانتقال من حركة نشطة إلى استقرار يرصد نهاية الإشارة (Apex/Boundary)', () {
      final analyzer = MotionAnalyzer(
        motionGateThreshold: 0.015,
        energyStartThreshold: 0.025,
      );

      // 1. الإطار الأول
      final f1 = createLandmarks(offsetX: 0.0, offsetY: 0.0);
      analyzer.analyze(f1);

      // 2. حركة قوية (بداية الإشارة)
      final f2 = createLandmarks(offsetX: 0.06, offsetY: 0.06);
      analyzer.analyze(f2);

      // 3. استمرار الحركة
      final f3 = createLandmarks(offsetX: 0.12, offsetY: 0.12);
      analyzer.analyze(f3);

      // 4. استقرار أول في وضع الإشارة (Apex)
      final f4 = createLandmarks(offsetX: 0.1205, offsetY: 0.1205);
      analyzer.analyze(f4);

      // 5. استقرار ثانٍ ➔ رصد حد الإشارة
      final f5 = createLandmarks(offsetX: 0.1208, offsetY: 0.1208);
      final res5 = analyzer.analyze(f5);

      expect(res5.isSignBoundary, isTrue, reason: 'التباطؤ والاستقرار بعد الحركة يمثل اكتمال حد الإشارة');
    });
  });
}
