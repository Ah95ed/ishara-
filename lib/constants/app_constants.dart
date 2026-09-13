class AppConstants {
  AppConstants._();

  static const String appName = 'إشارة';
  static const String appNameEn = 'Ishara';

  // ── أداء معالجة الإطارات (Frame Throttling: 10-15 FPS) ──
  static const int frameThrottleMs = 75; // ~13 FPS لتوفير البطارية والـ CPU
  static const double targetMinFps = 10.0;
  static const double targetMaxFps = 15.0;

  // ── بوابة الحركة وتحديد حدود الإشارة (Motion Gate & Boundary) ──
  static const double motionGateThreshold = 0.015; // عتبة الحركة الدنيا لاعتبار اليد متحركة
  static const double motionEnergyStartThreshold = 0.025; // بداية مقطع إشارة جديد
  static const double motionEnergyRestThreshold = 0.012; // استقرار الإشارة / Apex

  // ── النافذة الزمنية المتكيفة (Adaptive Temporal Window) ──
  static const int minTemporalWindow = 4; // نافذة سريعة للإشارات الواضحة
  static const int maxTemporalWindow = 8; // نافذة الإشارات الديناميكية
  static const double earlyExitConfidence = 0.72; // عتبة الاعتماد المبكر (Early Commit)

  // ── الثبات والتحكم بالتردد (Adaptive Hysteresis & Confidence Gate) ──
  static const double adoptConfidenceThreshold = 0.70; // عتبة معتدلة لاعتماد كلمة جديدة أثناء الحركة
  static const double adoptConfidenceThresholdStatic = 0.62; // عتبة مخفضة مقبولة عند استقرار وثبات اليد
  static const double retainConfidenceThreshold = 0.50; // عتبة مخفضة للاحتفاظ بالكلمة ومنع التذبذب
  static const double minConfidence = 0.55; // عتبة بوابة الثقة العامة (Confidence Gate)
  static const int debounceMs = 1200;
  static const int maxTextBufferLength = 50;

  // ── حدود الجملة وترجمة LLM ──
  static const int sentencePauseDurationMs = 1300; // مهلة توقف اليد لاعتبار الجملة مكتملة
  static const double ggufTemperature = 0.1;
  static const int ggufMaxTokens = 32;

  static const String modelAssetPath = 'assets/models/arsl_sign_model.tflite';
  static const String labelsAssetPath = 'assets/models/labels.txt';

  static const String ttsLanguage = 'ar-SA';
  static const double ttsSpeechRate = 0.5;
  static const double ttsPitch = 1.0;
  static const double ttsVolume = 1.0;

  static const int cameraResolutionWidth = 640;
  static const int cameraResolutionHeight = 480;

  static const String permissionDeniedMessage = 'نحتاج إذن الكاميرا حتى نتمكن من تحليل الإشارات';
  static const String permissionPermanentlyDeniedMessage = 'تم رفض إذن الكاميرا بشكل دائم. اذهب للإعدادات وتمكين الإذن';
  static const String cameraUnavailableMessage = 'الكاميرا غير متوفرة على هذا الجهاز';
  static const String modelLoadingMessage = 'جارٍ تحميل النموذج...';
  static const String modelReadyMessage = 'النموذج جاهز';
  static const String modelErrorTitle = 'تعذر تحميل النموذج';
  static const String modelErrorMessage = 'حدث خطأ أثناء تحميل نموذج التعرف';
  static const String recognizingMessage = 'جارٍ التعرف...';
  static const String noPredictionMessage = 'لم يتم التعرف بعد';
  static const String lowConfidenceMessage = 'لم يتم التعرف بوضوح';

  static const double aiConfidenceThreshold = 0.7;
  static const int aiCacheMaxAgeMs = 7 * 24 * 60 * 60 * 1000;
  static const String aiProviderKey = 'gemini';
}
