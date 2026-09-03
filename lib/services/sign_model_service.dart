import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/models/landmarks_model.dart';
import 'package:ishara/models/sign_prediction_model.dart';
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

  /// التنبؤ بالإشارة من معالم اليد الـ 21
  Future<SignPrediction?> predict(HandLandmarks landmarks) async {
    if (!_isModelLoaded || !landmarks.isValid || landmarks.landmarks.length < 21) {
      return null;
    }

    // 1. تشغيل المصنف الهندسي المستقل عن اتجاه دوران الكاميرا
    final geometricResult = _classifyGeometric(landmarks);

    // 2. محاولة تشغيل نموذج TFLite إذا كان متاحاً
    if (_interpreter != null) {
      try {
        final tfliteResult = _predictTflite(landmarks);
        if (tfliteResult != null) {
          // إذا تطابق النموذجان أو كانت ثقة TFLite عالية جداً
          if (geometricResult != null && geometricResult.label == tfliteResult.label) {
            return tfliteResult.copyWith(confidence: max(tfliteResult.confidence, 0.95));
          }
          if (tfliteResult.confidence >= 0.80) {
            return tfliteResult;
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[SignModelService] TFLite inference error: $e');
      }
    }

    // الاعتماد على المصنف الهندسي المستقر
    return geometricResult;
  }

  /// تصنيف هندسي دوراني ذكي يعتمد على بنية مفاصل اليد (Rotation-Invariant)
  SignPrediction? _classifyGeometric(HandLandmarks landmarks) {
    final pts = landmarks.landmarks;

    final p0 = pts[0]; // المعصم Wrist
    final p4 = pts[4]; // طرف الإبهام Thumb tip
    final p8 = pts[8]; // طرف السبابة Index tip
    final p12 = pts[12]; // طرف الوسطى Middle tip
    final p16 = pts[16]; // طرف البنصر Ring tip
    final p20 = pts[20]; // طرف الخنصر Pinky tip

    // مفاصل اليد الأساسية (PIP / MCP)
    final p6 = pts[6]; // مفصل السبابة PIP
    final p9 = pts[9]; // قاعدة الوسطى Middle MCP
    final p10 = pts[10]; // مفصل الوسطى PIP
    final p14 = pts[14]; // مفصل البنصر PIP
    final p18 = pts[18]; // مفصل الخنصر PIP

    // مقياس حجم كف اليد (مسافة المعصم إلى قاعدة الوسطى)
    final palmScale = _dist(p0, p9).clamp(0.01, 10.0);

    // فحص امتداد كل إصبع مقارنة ببعده عن المعصم
    final bool indexExtended = _dist(p8, p0) > _dist(p6, p0) * 1.15;
    final bool middleExtended = _dist(p12, p0) > _dist(p10, p0) * 1.15;
    final bool ringExtended = _dist(p16, p0) > _dist(p14, p0) * 1.15;
    final bool pinkyExtended = _dist(p20, p0) > _dist(p18, p0) * 1.15;

    // فحص الإبهام (ممتد للخارج أم مضموم)
    final bool thumbExtended = _dist(p4, p9) > palmScale * 0.70;
    // تقارب الإبهام والسبابة (علامة القرص Pinch / حرف ف)
    final bool thumbIndexPinch = _dist(p4, p8) < palmScale * 0.35;
    // تقارب كل الأصابع معاً في نقطة واحدة (طعام)
    final bool allTipsTouching = _dist(p4, p8) < palmScale * 0.40 &&
        _dist(p4, p12) < palmScale * 0.45 &&
        _dist(p4, p16) < palmScale * 0.45 &&
        _dist(p4, p20) < palmScale * 0.50;

    // مسافات بينية بين رؤوس الأصابع
    final double indexMiddleGap = _dist(p8, p12) / palmScale;

    String label = '';
    double confidence = 0.88;

    // ────────────────────────────────── قواعد التعرف على الإشارات والكلمات ──────────────────────────────────

    // 1. طعام (جميع أطراف الأصابع مجتمعة)
    if (allTipsTouching) {
      label = 'طعام';
      confidence = 0.94;
    }
    // 2. مساعدة / Thumbs Up (الإبهام ممتد وجميع الأصابع الـ 4 مطوية بقبضة)
    else if (thumbExtended && !indexExtended && !middleExtended && !ringExtended && !pinkyExtended) {
      label = 'مساعدة';
      confidence = 0.92;
    }
    // 3. ل (L-shape: الإبهام ممتد بزاوية قائمة + السبابة ممتدة + باقي الأصابع مطوية)
    else if (thumbExtended && indexExtended && !middleExtended && !ringExtended && !pinkyExtended) {
      label = 'ل';
      confidence = 0.95;
    }
    // 4. أ / Alef (السبابة ممتدة فقط وباقي الأصابع مطوية)
    else if (indexExtended && !middleExtended && !ringExtended && !pinkyExtended) {
      label = 'أ';
      confidence = 0.93;
    }
    // 5. ي / Ya2 (الخنصر ممتد فقط وباقي الأصابع مطوية)
    else if (pinkyExtended && !indexExtended && !middleExtended && !ringExtended) {
      label = 'ي';
      confidence = 0.95;
    }
    // 6. ف / Fa2 (قرص بين الإبهام والسبابة + الأصابع الثلاثة ممتدة للأعلى كعلامة OK)
    else if (thumbIndexPinch && middleExtended && ringExtended && pinkyExtended) {
      label = 'ف';
      confidence = 0.92;
    }
    // 7. ع / 3ayn (السبابة والوسطى ممتدتان ومتباعدتان على شكل V)
    else if (indexExtended && middleExtended && !ringExtended && !pinkyExtended && indexMiddleGap > 0.35) {
      label = 'ع';
      confidence = 0.92;
    }
    // 8. ت / Ta2 (السبابة والوسطى ممتدتان ومتلاصقتان للأعلى)
    else if (indexExtended && middleExtended && !ringExtended && !pinkyExtended && indexMiddleGap <= 0.35) {
      label = 'ت';
      confidence = 0.90;
    }
    // 9. ماء / ث (ثلاثة أصابع ممتدة: السبابة + الوسطى + البنصر مع طي الخنصر)
    else if (indexExtended && middleExtended && ringExtended && !pinkyExtended) {
      // إشارة W الشهيرة للماء في لغة الإشارة
      label = 'ماء';
      confidence = 0.94;
    }
    // 10. ب / Ba2 (الأصابع الأربعة ممتدة معاً للأعلى والإبهام مطوي فوق الكف)
    else if (indexExtended && middleExtended && ringExtended && pinkyExtended && !thumbExtended) {
      label = 'ب';
      confidence = 0.91;
    }
    // 11. السلام / كف مفتوح بالكامل (جميع الأصابع الـ 5 ممتدة ومفتوحة)
    else if (indexExtended && middleExtended && ringExtended && pinkyExtended && thumbExtended) {
      label = 'السلام';
      confidence = 0.96;
    }
    // 12. م / Mim (قبضة يد مغلقة بالكامل Fist)
    else if (!indexExtended && !middleExtended && !ringExtended && !pinkyExtended) {
      label = 'م';
      confidence = 0.90;
    }

    if (label.isEmpty) {
      return null;
    }

    return SignPrediction(
      label: label,
      confidence: confidence,
      timestamp: DateTime.now(),
      handedness: landmarks.handedness,
    );
  }

  /// استنتاج نموذج TFLite الرسمي
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

    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > maxProb) {
        maxProb = probs[i];
        maxIdx = i;
      }
    }

    if (maxProb < 0.35 || maxIdx >= _labels.length) {
      return null;
    }

    final rawLabel = _labels[maxIdx];
    final arabicLabel = arabicLabelMap[rawLabel] ?? rawLabel;

    return SignPrediction(
      label: arabicLabel,
      confidence: maxProb.clamp(0.0, 1.0),
      timestamp: DateTime.now(),
      handedness: landmarks.handedness,
      signId: maxIdx,
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
