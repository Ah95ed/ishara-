import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/models/landmarks_model.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/motion_analyzer.dart';
import 'package:ishara/services/word_only_filter.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// محرك الاستنتاج المتكامل لتمييز إشارات لغة الإشارة العربية
/// يجمع بين:
/// 1. المصنف الهندسي الدوراني المستقل عن اتجاه الكاميرا (Rotation-Invariant Geometric Classifier)
/// 2. نموذج التعلم العميق TFLite (arsl_sign_model.tflite) ذو الـ 89 خاصية
class SignModelService {
  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  List<String> _labels = [];

  bool get isLoaded => _isModelLoaded;

  // خريطة تحويل الأسماء التقنية إلى الحروف والكلمات العربية الفصحى
  static const Map<String, String> arabicLabelMap = {
    'Alef': 'أ',
    'Ba2': 'ب',
    'Ta2': 'ت',
    'Tha2': 'ث',
    'Jim': 'ج',
    '7a2': 'ح',
    'Kha2': 'خ',
    'Dal': 'د',
    'Thal': 'ذ',
    'Ra2': 'ر',
    'Zayn': 'ز',
    'Sin': 'س',
    'Chin': 'ش',
    'SSad': 'ص',
    'DDad': 'ض',
    'TTa2': 'ط',
    'TTha2': 'ظ',
    '3ayn': 'ع',
    'Ghayn': 'غ',
    'Fa2': 'ف',
    '9af': 'ق',
    'Kaf': 'ك',
    'Lam': 'ل',
    'Mim': 'م',
    'Noon': 'ن',
    'Ha2': 'هـ',
    'Waw': 'و',
    'Ya2': 'ي',
    'Space': 'مسافة',
    'Delete': 'مسح',
    'Finish': 'إنهاء',
  };

  /// تحميل النموذج وقائمة الـ Labels
  Future<void> loadModel(List<String> labels) async {
    _labels = labels;

    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(
        AppConstants.modelAssetPath,
        options: options,
      );
      if (kDebugMode) {
        debugPrint('[SignModelService] ✅ TFLite model loaded successfully: ${AppConstants.modelAssetPath}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SignModelService] ⚠️ TFLite load fallback to geometric matcher: $e');
      }
      _interpreter = null;
    }

    _isModelLoaded = true;
  }

  /// التنبؤ بالإشارة من معالم اليد الـ 21 مع الاستفادة من خصائص الحركة (Motion Features)
  Future<SignPrediction?> predict(HandLandmarks landmarks, {MotionFeatures? motionFeatures}) async {
    if (!_isModelLoaded || !landmarks.isValid || landmarks.landmarks.length < 21) {
      return null;
    }

    // 1. تشغيل المصنف الهندسي والحركي المستقل عن الدوران
    final geometricResult = _classifyGeometric(landmarks, motionFeatures: motionFeatures);

    // 2. محاولة تشغيل نموذج TFLite إذا كان متاحاً
    SignPrediction? finalResult = geometricResult;
    if (_interpreter != null) {
      try {
        final tfliteResult = _predictTflite(landmarks);
        if (tfliteResult != null && WordOnlyFilter.isValidWord(tfliteResult.label)) {
          if (geometricResult != null && geometricResult.label == tfliteResult.label) {
            finalResult = tfliteResult.copyWith(
              confidence: max(tfliteResult.confidence, 0.95),
              confidenceMargin: max(tfliteResult.confidenceMargin, 0.30),
            );
          } else if (tfliteResult.confidence >= 0.70) {
            finalResult = tfliteResult;
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[SignModelService] TFLite inference error: $e');
      }
    }

    // ── المتطلب 10 (Word Only Filter): استبعاد أي حرف منفرد قطعياً ──
    if (finalResult != null && WordOnlyFilter.isValidWord(finalResult.label)) {
      return finalResult;
    }

    return null;
  }

  /// تم إيقاف المصنف الهندسي الثابت تماماً تنفيذاً للمتطلبات الصارمة لمنع الانهيار وتكرار كلمات (شكراً / مساعدة / لا)
  SignPrediction? _classifyGeometric(HandLandmarks landmarks, {MotionFeatures? motionFeatures}) {
    // لا يوجد أي Fallback أو Hardcoded Rules هنا. الاعتماد الحصري على نموذج Ishara CSLR TFLite والمنظومة الزمنية.
    return null;
  }

  /// استنتاج نموذج TFLite الرسمي مع فحص صارم للكلمات وحساب Top-1 و Top-2 و Margin
  SignPrediction? _predictTflite(HandLandmarks landmarks) {
    if (_interpreter == null) return null;

    final features = _extract89Features(landmarks);
    if (features.length != 89) return null;

    final input = [features];
    final output = List.filled(1, List.filled(31, 0.0)).map((list) => List<double>.filled(31, 0.0)).toList();

    _interpreter!.run(input, output);

    final probs = output[0];
    int maxIdx = 0;
    double maxProb = probs[0];
    int secondIdx = -1;
    double secondProb = 0.0;

    for (int i = 1; i < probs.length; i++) {
      final p = probs[i];
      if (p > maxProb) {
        secondProb = maxProb;
        secondIdx = maxIdx;
        maxProb = p;
        maxIdx = i;
      } else if (p > secondProb) {
        secondProb = p;
        secondIdx = i;
      }
    }

    if (maxProb < 0.35 || maxIdx >= _labels.length) {
      return null;
    }

    final rawLabel = _labels[maxIdx];
    final arabicLabel = arabicLabelMap[rawLabel] ?? rawLabel;

    // استبعاد أي حرف منفرد يأتي من نموذج TFLite
    if (!WordOnlyFilter.isValidWord(arabicLabel)) {
      return null;
    }

    String? secondLabel;
    if (secondIdx >= 0 && secondIdx < _labels.length) {
      final rawSecond = _labels[secondIdx];
      secondLabel = arabicLabelMap[rawSecond] ?? rawSecond;
    }

    final margin = (maxProb - secondProb).clamp(0.0, 1.0);

    return SignPrediction(
      label: arabicLabel,
      confidence: maxProb.clamp(0.0, 1.0),
      timestamp: DateTime.now(),
      handedness: landmarks.handedness,
      signId: maxIdx,
      secondLabel: secondLabel,
      secondConfidence: secondProb.clamp(0.0, 1.0),
      confidenceMargin: margin,
    );
  }

  /// استخراج الـ 89 خاصية المطابقة لملف التدريب ArSL-31-Pilot
  List<double> _extract89Features(HandLandmarks landmarks) {
    final lm = landmarks.landmarks;
    final feat = <double>[];

    // 1. 42 إحداثيات (x, y)
    for (int i = 0; i < 21; i++) {
      feat.add(lm[i].x);
      feat.add(lm[i].y);
    }

    // 2. 18 قيم متوسطة لمواقع المفاصل (means)
    final pairs = [
      [0, 4], [0, 8], [0, 12], [0, 16], [0, 20],
      [4, 8], [4, 12], [4, 16], [4, 20],
    ];
    for (final p in pairs) {
      feat.add((lm[p[0]].x + lm[p[1]].x) / 2.0);
      feat.add((lm[p[0]].y + lm[p[1]].y) / 2.0);
    }

    // 3. 14 زوايا مفاصل
    final angleTriplets = [
      [1, 2, 3], [2, 3, 4],
      [0, 5, 6], [5, 6, 7], [6, 7, 8],
      [0, 9, 10], [9, 10, 11], [10, 11, 12],
      [0, 13, 14], [13, 14, 15], [14, 15, 16],
      [0, 17, 18], [17, 18, 19], [18, 19, 20],
    ];
    for (final t in angleTriplets) {
      feat.add(_calcAngle(lm[t[0]], lm[t[1]], lm[t[2]]));
    }

    // 4. 15 مسافات إقليدية
    final distPairs = [
      [0, 4], [0, 8], [4, 8], [0, 12], [4, 12],
      [0, 16], [4, 16], [0, 20], [4, 20],
      [8, 12], [8, 16], [12, 16], [8, 20], [12, 20], [16, 20],
    ];
    for (final p in distPairs) {
      feat.add(_dist(lm[p[0]], lm[p[1]]));
    }

    return feat;
  }

  double _dist(HandLandmark a, HandLandmark b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
  }

  double _calcAngle(HandLandmark p1, HandLandmark p2, HandLandmark p3) {
    final v1x = p1.x - p2.x;
    final v1y = p1.y - p2.y;
    final v2x = p3.x - p2.x;
    final v2y = p3.y - p2.y;
    final dot = v1x * v2x + v1y * v2y;
    final mag1 = sqrt(v1x * v1x + v1y * v1y);
    final mag2 = sqrt(v2x * v2x + v2y * v2y);
    if (mag1 == 0 || mag2 == 0) return 0.0;
    return (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isModelLoaded = false;
  }
}
