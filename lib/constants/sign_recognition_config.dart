/// إعدادات وثوابت منظومة التعرف على لغة الإشارة (BiLSTM/TFLite + Gloss2Text)
///
/// تم تجميع كافة العتبات وقيم النوافذ الزمنية في هذا المكان لتسهيل
/// المعايرة والضبط الميداني بعد الاختبار على الأجهزة الفعلية.
class SignRecognitionConfig {
  SignRecognitionConfig._();

  // ──────────────────────────────── 1. طبقة رفض القرار الضعيف (Rejection Layer) ────────────────────────────────
  /// الحد الأدنى لثقة أعلى تصنيف (Top-1 Absolute Confidence)
  /// يبدأ بقيمة متوازنة معتدلة (0.55 - 0.65) لمنع التخمينات الضعيفة
  static const double minConfidence = 0.60;

  /// الفرق الأدنى المطلوب بين أعلى تصنيفين (Top-1 Confidence - Top-2 Confidence Margin)
  /// إذا كان الفارق أقل من هذا الحد، يعتبر النموذج "متردداً" بين كلمتين ويرفض القرار
  static const double confidenceMargin = 0.15;

  /// عتبة الطاقة الحركية الدنيا لاعتبار اليد في حالة حركة (Kinetic Energy Threshold)
  /// إذا كانت الحركة أقل من هذا الحد، تعتبر اليد في حالة سكون (IDLE / NO_SIGN)
  static const double minMotionEnergy = 0.018;

  /// عتبة السرعة الدنيا لحركة اليد (Velocity Threshold)
  static const double minVelocity = 0.025;

  // ──────────────────────────────── 2. آلة الحالة الزمنية (Temporal State Machine) ────────────────────────────────
  /// حجم النافذة الزمنية المنزلقة (Sliding Window Size: 8 - 12 إطار)
  static const int stableWindowSize = 10;

  /// الحد الأدنى للنافذة المتكيفة (للإشارات شديدة الوضوح)
  static const int minWindowSize = 6;

  /// الحد الأقصى للنافذة المتكيفة
  static const int maxWindowSize = 12;

  /// نسبة التصويت الأغلبي المطلوبة داخل النافذة (Majority Voting Ratio: مثلاً 60%)
  static const double majorityVoteRatio = 0.60;

  /// عتبة التبني بالاعتماد المبكر عند وضوح فائق للإشارة عبر 3 إطارات متتالية
  static const double earlyExitConfidence = 0.85;

  /// عدد الإطارات الإلزامية لفترة التبريد (Cooldown Frames: يعادل تقريباً مدة نافذة الاستقرار)
  static const int cooldownFrames = 12;

  /// مدة فترة التبريد الزمنية بالمللي ثانية (Cooldown Duration)
  static const int cooldownDurationMs = 1000;

  /// قفزة الحركة المطلوبة لكسر فترة التبريد والانتقال لإشارة جديدة (Motion Spike Threshold)
  static const double motionSpikeBreakThreshold = 0.045;

  /// طاقة الحركة المطلوبة لكسر التبريد
  static const double motionEnergyBreakThreshold = 0.040;

  // ──────────────────────────────── 3. مخزن الكلمات وحدود الجملة (Gloss Buffer & Sentence Boundary) ────────────────────────────────
  /// مدة سكون اليد لاعتبار الجملة مكتملة وترجمتها (Sentence-end silence: 2.5 - 3 أضعاف الـ Cooldown)
  static const int sentenceEndSilenceMs = 3000;

  /// الحد الأقصى لعدد الكلمات في الـ Gloss Buffer قبل فرض الترجمة آلياً
  static const int maxBufferWords = 7;

  /// مهلة انقطاع اليد من الكاميرا قبل تصفير الذاكرة الحركية المؤقتة
  static const int handResetTimeoutMs = 800;

  // ──────────────────────────────── 4. إعدادات نموذج الترجمة (Gloss2Text Gemma3 GGUF) ────────────────────────────────
  /// درجة حرارة توليد النص للترجمة الدقيقة (Temperature)
  static const double ggufTemperature = 0.1;

  /// الحد الأقصى لرموز التوليد للجملة المترجمة
  static const int ggufMaxTokens = 32;
}
