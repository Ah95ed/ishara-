# إشارة - Ishara

تطبيق Flutter لترجمة لغة الإشارة العربية إلى نص عربي باستخدام كاميرا الهاتف والذكاء الاصطناعي.

## الفكرة

الشخص يفتح الكاميرا ويبدأ باستخدام إشارات لغة الإشارة، والتطبيق يحاول يتعرف عليها ويعرض الكلام المكتوب. بعدين المستخدم يقدر يشغّل النطق.

البداية بسيطة، وبعدها أطور التعرف على كلمات أكثر وجمل كاملة.

## المميزات

- التعرف على الإشارات من الكاميرا
- working real-time
- تحويل الإشارة إلى نص عربي
- نطق النص بالعربية
- واجهة بسيطة وهادئة
- تصميم متجاوب (شاشات صغيرة، أجهزة لوحية، landscape و portrait)
- Temporal processing عشان ما تتكرر نفس الكلمة
- معالجة الأخطاء بسيطة وواضحة

## العيوب والقيود

- النموذج الحالي تجريبي ولا يفهم كل لغة الإشارة.
- دقة التعرف تعتمد على بيانات التدريب.
- الإضاءة وزاوية الكاميرا والمسافة ممكن تأثر على النتيجة.
- الإشارات المستمرة والجمل الكاملة تحتاج dataset زمنية أكبر.
- تعبيرات الوجه وحركة الجسم تحتاج تطوير إضافي.

## التقنيات

- Flutter + Dart
- Provider لإدارة الحالة
- MVC للتنظيم
- Material 3
- Camera package
- MediaPipe / Google ML Kit (للـ landmarks)
- TensorFlow Lite / LiteRT
- flutter_tts للنطق
- responsive_framework

## هيكل المشروع

```
lib/
  main.dart
  theme/
    app_theme.dart
    app_colors.dart
  constants/
    app_constants.dart
  utils/
    app_extensions.dart
  models/
    camera_state_model.dart
    landmarks_model.dart
    sign_prediction_model.dart
  repositories/
    sign_repository.dart
  services/
    camera_service.dart
    landmark_service.dart
    ml_service.dart
    speech_service.dart
  controllers/
    camera_controller.dart
    sign_controller.dart
    speech_controller.dart
  widgets/
    camera_preview_widget.dart
    confidence_widget.dart
    controls_widget.dart
    result_text_widget.dart
  views/
    home_view.dart
```

## طريقة التشغيل

### المتطلبات

- Flutter SDK ^3.13.0
- Android SDK
- emulator أو جهاز حقيقي فيه كاميرا

### تشغيل المشروع

```bash
flutter pub get
flutter run
```

### بناء APK

```bash
flutter build apk --debug
```

الـ APK بيطلع في:
```
build/app/outputs/flutter-apk/app-debug.apk
```

### ملاحظات على البناء للأندرويد

المشروع يستخدم camera و flutter_tts و tflite_flutter. قد تحتاج تعديل إعدادات Gradle حسب إصدار Android Studio المحلي.

## النموذج حالياً

المرحلة الأولى ركزت على بناء الهيكل والواجهة وكاميرا و temporal processing.

النموذج الحالي يعمل على isolated sign recognition. بعدين نضيف:
- temporal model
- hand movement
- face landmarks
- pose
- جمل كاملة

## المستقبل

- دعم كلمات أكثر
- دعم الحركات المتسلسلة
- تحسين اللغة العربية
- إضافة تعبير الوجه
- إضافة Pose
- ترجمة الجمل
- Speech To Sign
- شخصية ثلاثية الأبعاد للغة الإشارة

## الرخصة

هذا المشروع للاستخدام التعليمي والتطوير.
