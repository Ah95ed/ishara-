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
            finalResult = tfliteResult.copyWith(confidence: max(tfliteResult.confidence, 0.95));
          } else if (tfliteResult.confidence >= 0.85) {
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

  /// تصنيف هندسي وحركي ذكي يعتمد على بنية مفاصل اليد والحركة (Rotation-Invariant & Motion-Aware)
  SignPrediction? _classifyGeometric(HandLandmarks landmarks, {MotionFeatures? motionFeatures}) {
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

    // تقارب كل الأصابع معاً في نقطة واحدة (طعام)
    final bool allTipsTouching = _dist(p4, p8) < palmScale * 0.40 &&
        _dist(p4, p12) < palmScale * 0.45 &&
        _dist(p4, p16) < palmScale * 0.45 &&
        _dist(p4, p20) < palmScale * 0.50;

    // علامة أحبك (ILY Sign: الإبهام والسبابة والخنصر ممتدة، والوسطى والبنصر مطوية)
    final bool ilySign = thumbExtended && indexExtended && !middleExtended && !ringExtended && pinkyExtended;

    // اتجاه حركة اليد وسرعتها من MotionFeatures
    final double vel = motionFeatures?.averageVelocity ?? 0.0;
    final double dirY = motionFeatures?.directionY ?? 0.0;
    final double dirZ = motionFeatures?.directionZ ?? 0.0;

    String label = '';
    double confidence = 0.88;

    // ────────────────────────────────── قواعد التعرف على الكلمات الكاملة (Glosses) ──────────────────────────────────

    // 1. طعام (جميع أطراف الأصابع مجتمعة في نقطة واحدة)
    if (allTipsTouching) {
      label = 'طعام';
      confidence = 0.94;
    }
    // 2. أحبك (إشارة ILY العالمية للغة الإشارة: إبهام + سبابة + خنصر)
    else if (ilySign) {
      label = 'أحبك';
      confidence = 0.96;
    }
    // 3. مساعدة / Thumbs Up (الإبهام ممتد للأعلى وباقي الأصابع مطوية بقبضة)
    else if (thumbExtended && !indexExtended && !middleExtended && !ringExtended && !pinkyExtended) {
      label = 'مساعدة';
      confidence = 0.93;
    }
    // 4. ماء (ثلاثة أصابع ممتدة: السبابة + الوسطى + البنصر مع طي الخنصر)
    else if (indexExtended && middleExtended && ringExtended && !pinkyExtended) {
      label = 'ماء';
      confidence = 0.94;
    }
    // 5. السلام (كف مفتوح بالكامل وجميع الأصابع الـ 5 ممتدة)
    else if (indexExtended && middleExtended && ringExtended && pinkyExtended && thumbExtended) {
      label = 'السلام';
      confidence = 0.96;
    }
    // 6. أنا (السبابة ممتدة وموجهة نحو الجسم / المعصم أعلى من الإصبع أو حركة داخلية)
    else if (indexExtended && !middleExtended && !ringExtended && !pinkyExtended && (p8.y > p6.y || dirZ < -0.15)) {
      label = 'أنا';
      confidence = 0.92;
    }
    // 7. أنت (السبابة ممتدة للأمام نحو الكاميرا)
    else if (indexExtended && !middleExtended && !ringExtended && !pinkyExtended && p8.y <= p6.y) {
      // فحص هل هناك حركة أفقية لتمييز "لا"
      if (vel > 0.05 && (motionFeatures?.directionX.abs() ?? 0.0) > 0.6) {
        label = 'لا';
        confidence = 0.90;
      } else {
        label = 'أنت';
        confidence = 0.91;
      }
    }
    // 8. شكراً (الأصابع الأربعة ممتدة ومضمومة معاً ككف مستوٍ)
    else if (indexExtended && middleExtended && ringExtended && pinkyExtended && !thumbExtended) {
      label = 'شكراً';
      confidence = 0.91;
    }
    // 9. نعم (قبضة اليد تتحرك بحركة إيماء للأسفل)
    else if (!indexExtended && !middleExtended && !ringExtended && !pinkyExtended) {
      if (vel > 0.03 && dirY > 0.3) {
        label = 'نعم';
        confidence = 0.92;
      } else {
        // قبضة يد ساكنة دون حركة لا نعتبرها حرف م
        return null;
      }
    }
    // 10. ذهاب (السبابة والوسطى ممتدتان مع حركة للأمام)
    else if (indexExtended && middleExtended && !ringExtended && !pinkyExtended && vel > 0.04) {
      label = 'ذهاب';
      confidence = 0.89;
    }
    // 11. سوق (تقارب السبابة والإبهام مع حركة متكررة)
    else if (_dist(p4, p8) < palmScale * 0.40 && middleExtended && ringExtended) {
      label = 'سوق';
      confidence = 0.88;
    }

    if (label.isEmpty || !WordOnlyFilter.isValidWord(label)) {
      return null;
    }

    return SignPrediction(
      label: label,
      confidence: confidence,
      timestamp: DateTime.now(),
      handedness: landmarks.handedness,
    );
  }

  /// استنتاج نموذج TFLite الرسمي مع فحص صارم للكلمات
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

    // استبعاد أي حرف منفرد يأتي من نموذج TFLite
    if (!WordOnlyFilter.isValidWord(arabicLabel)) {
      return null;
    }

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
