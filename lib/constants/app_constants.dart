class AppConstants {
  AppConstants._();

  static const String appName = 'إشارة';
  static const String appNameEn = 'Ishara';

  static const int frameThrottleMs = 100;
  static const int temporalWindowSize = 5;
  static const int debounceMs = 1500;
  static const double minConfidence = 0.65;
  static const int maxTextBufferLength = 50;

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
