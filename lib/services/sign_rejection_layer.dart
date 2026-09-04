import 'package:ishara/constants/sign_recognition_config.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/motion_analyzer.dart';
import 'package:ishara/services/word_only_filter.dart';

/// أسباب الرفض الصريحة في طبقة التحقق
enum RejectionReason {
  none,            // مقبول
  idle,            // اليد في حالة سكون أو طاقة الحركة ضعيفة جداً (IDLE / NO_SIGN)
  lowConfidence,   // الثقة أقل من الحد الأدنى المقبول
  undecidedMargin, // الفرق بين Top-1 و Top-2 ضئيل (النموذج متردد وغير محسوم)
  invalidWord,     // ليس كلمة صالحة (حرف منفرد أو رمز غير معتمد)
  noPrediction,    // لا يوجد تنبؤ متاح
}

/// نتيجة تقييم طبقة الرفض
class RejectionEvaluation {
  final bool isAccepted;
  final bool isIdle;
  final RejectionReason reason;
  final SignPrediction? prediction;
  final String description;

  const RejectionEvaluation({
    required this.isAccepted,
    required this.isIdle,
    required this.reason,
    this.prediction,
    required this.description,
  });

  factory RejectionEvaluation.accepted(SignPrediction prediction) {
    return RejectionEvaluation(
      isAccepted: true,
      isIdle: false,
      reason: RejectionReason.none,
      prediction: prediction,
      description: 'تم قبول المرشح: ${prediction.label} (ثقة: ${(prediction.confidence * 100).toStringAsFixed(0)}%, هامش: ${(prediction.confidenceMargin * 100).toStringAsFixed(0)}%)',
    );
  }

  factory RejectionEvaluation.idle({String reasonText = 'اليد في حالة سكون (IDLE / NO_SIGN)'}) {
    return RejectionEvaluation(
      isAccepted: false,
      isIdle: true,
      reason: RejectionReason.idle,
      description: reasonText,
    );
  }

  factory RejectionEvaluation.rejected({
    required RejectionReason reason,
    SignPrediction? prediction,
    required String description,
  }) {
    return RejectionEvaluation(
      isAccepted: false,
      isIdle: reason == RejectionReason.idle,
      reason: reason,
      prediction: prediction?.copyWith(
        isRejected: true,
        rejectionReason: description,
      ),
      description: description,
    );
  }
}

/// طبقة رفض القرار الضعيف (Rejection Layer)
///
/// تحقق المتطلبات الصارمة:
/// 1. Motion Energy: لو حركة اليد شبه سكون -> اعتبرها IDLE / NO_SIGN صريحة بغض النظر عن الثقة.
/// 2. Confidence المطلق: أعلى احتمال يجب أن يتجاوز حد أدنى (0.55 - 0.65).
/// 3. Confidence Margin: الفرق بين أعلى فئتين (Top-1 و Top-2) يجب أن يتجاوز 0.15 لمنع تردد النموذج.
/// 4. Word Only Filter: استبعاد أي حرف منفرد قطعياً.
class SignRejectionLayer {
  final double minConfidence;
  final double confidenceMargin;
  final double minMotionEnergy;
  final double minVelocity;

  const SignRejectionLayer({
    this.minConfidence = SignRecognitionConfig.minConfidence,
    this.confidenceMargin = SignRecognitionConfig.confidenceMargin,
    this.minMotionEnergy = SignRecognitionConfig.minMotionEnergy,
    this.minVelocity = SignRecognitionConfig.minVelocity,
  });

  /// تقييم التنبؤ مع خصائص الحركة اللحظية
  RejectionEvaluation evaluate({
    required SignPrediction? prediction,
    required MotionFeatures motion,
  }) {
    // 1. فحص الطاقة الحركية (Motion Energy & Velocity Check)
    // إذا كانت اليد ساكنة أو تحت عتبة الحركة الدنيا، نعتبرها IDLE فوراً
    final bool isMotionBelowMin = motion.motionEnergy < minMotionEnergy && motion.averageVelocity < minVelocity;
    final bool isEffectivelyStatic = motion.isHandStatic && motion.averageVelocity < (minVelocity * 1.2);

    if (isMotionBelowMin || isEffectivelyStatic) {
      return RejectionEvaluation.idle(
        reasonText: 'سكون اليد: طاقة الحركة ${(motion.motionEnergy * 1000).toStringAsFixed(1)} < ${(minMotionEnergy * 1000).toStringAsFixed(1)}',
      );
    }

    // 2. التحقق من وجود تنبؤ
    if (prediction == null) {
      return RejectionEvaluation.rejected(
        reason: RejectionReason.noPrediction,
        description: 'لا يوجد تنبؤ من النموذج',
      );
    }

    // 3. التحقق من مرشح الكلمات الصارم (WordOnlyFilter)
    if (!WordOnlyFilter.isValidWord(prediction.label)) {
      return RejectionEvaluation.rejected(
        reason: RejectionReason.invalidWord,
        prediction: prediction,
        description: 'حرف منفرد أو رمز غير مقبول: "${prediction.label}"',
      );
    }

    // 4. فحص الثقة المطلقة (Absolute Confidence Check)
    if (prediction.confidence < minConfidence) {
      return RejectionEvaluation.rejected(
        reason: RejectionReason.lowConfidence,
        prediction: prediction,
        description: 'ثقة منخفضة: ${(prediction.confidence * 100).toStringAsFixed(1)}% < ${(minConfidence * 100).toStringAsFixed(0)}%',
      );
    }

    // 5. فحص هامش الثقة بين الفئتين الأوليين (Confidence Margin Check: Top-1 vs Top-2)
    // إذا كان الموديل متردداً بين كلمتين متقاربتين، نرفض القرار
    if (prediction.confidenceMargin < confidenceMargin) {
      return RejectionEvaluation.rejected(
        reason: RejectionReason.undecidedMargin,
        prediction: prediction,
        description: 'قرار غير محسوم: فارق الثقة ${(prediction.confidenceMargin * 100).toStringAsFixed(1)}% < ${(confidenceMargin * 100).toStringAsFixed(0)}% (بين ${prediction.label} و ${prediction.secondLabel ?? "غيره"})',
      );
    }

    // كافة الشروط مستوفاة ➔ قبول كمرشح صالح
    return RejectionEvaluation.accepted(prediction);
  }
}
