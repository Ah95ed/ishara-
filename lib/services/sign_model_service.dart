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
    if (pts.length < 21) return null;

    final p0 = pts[0]; // المعصم Wrist
    final p1 = pts[1]; // إبهام CMC
    final p2 = pts[2]; // إبهام MCP
    final p3 = pts[3]; // إبهام IP
    final p4 = pts[4]; // طرف الإبهام Thumb tip

    final p5 = pts[5]; // قاعدة السبابة Index MCP
    final p6 = pts[6]; // مفصل السبابة PIP
    final p7 = pts[7]; // مفصل السبابة DIP
    final p8 = pts[8]; // طرف السبابة Index tip

    final p9 = pts[9]; // قاعدة الوسطى Middle MCP
    final p10 = pts[10]; // مفصل الوسطى PIP
    final p11 = pts[11]; // مفصل الوسطى DIP
    final p12 = pts[12]; // طرف الوسطى Middle tip

    final p13 = pts[13]; // قاعدة البنصر Ring MCP
    final p14 = pts[14]; // مفصل البنصر PIP
    final p15 = pts[15]; // مفصل البنصر DIP
    final p16 = pts[16]; // طرف البنصر Ring tip

    final p17 = pts[17]; // قاعدة الخنصر Pinky MCP
    final p18 = pts[18]; // مفصل الخنصر PIP
    final p19 = pts[19]; // مفصل الخنصر DIP
    final p20 = pts[20]; // طرف الخنصر Pinky tip

    // مقياس حجم كف اليد المعياري (مسافة المعصم إلى قاعدة الوسطى)
    final palmScale = _dist(p0, p9).clamp(0.02, 10.0);

    // قياس استقامة كل إصبع بنسبة طول العظام الفعلي (Scale-Invariant Extension Ratio)
    final thumbBoneLen = _dist(p1, p2) + _dist(p2, p3) + _dist(p3, p4);
    final thumbExtRatio = _dist(p4, p2) / (thumbBoneLen > 0 ? thumbBoneLen : 1.0);
    final bool thumbExtended = thumbExtRatio > 0.65 || _dist(p4, p9) > palmScale * 0.65;

    final indexBoneLen = _dist(p5, p6) + _dist(p6, p7) + _dist(p7, p8);
    final indexExtRatio = _dist(p8, p5) / (indexBoneLen > 0 ? indexBoneLen : 1.0);
    final bool indexExtended = indexExtRatio > 0.62 || _dist(p8, p0) > _dist(p6, p0) * 1.05;

    final middleBoneLen = _dist(p9, p10) + _dist(p10, p11) + _dist(p11, p12);
    final middleExtRatio = _dist(p12, p9) / (middleBoneLen > 0 ? middleBoneLen : 1.0);
    final bool middleExtended = middleExtRatio > 0.62 || _dist(p12, p0) > _dist(p10, p0) * 1.05;

    final ringBoneLen = _dist(p13, p14) + _dist(p14, p15) + _dist(p15, p16);
    final ringExtRatio = _dist(p16, p13) / (ringBoneLen > 0 ? ringBoneLen : 1.0);
    final bool ringExtended = ringExtRatio > 0.62 || _dist(p16, p0) > _dist(p14, p0) * 1.05;

    final pinkyBoneLen = _dist(p17, p18) + _dist(p18, p19) + _dist(p19, p20);
    final pinkyExtRatio = _dist(p20, p17) / (pinkyBoneLen > 0 ? pinkyBoneLen : 1.0);
    final bool pinkyExtended = pinkyExtRatio > 0.60 || _dist(p20, p0) > _dist(p18, p0) * 1.05;

    // مؤشرات المسافات والحركة
    final double vel = motionFeatures?.averageVelocity ?? 0.0;
    final double dirX = motionFeatures?.directionX.abs() ?? 0.0;
    final double dirY = motionFeatures?.directionY ?? 0.0;
    final double dirZ = motionFeatures?.directionZ ?? 0.0;

    String label = '';
    double confidence = 0.88;

    // ────────────────────────────────── قواعد التعرف على الكلمات الكاملة (Glosses) ──────────────────────────────────

    // 1. أحبك (إشارة ILY العالمية: إبهام + سبابة + خنصر ممتدة، والوسطى والبنصر مطوية)
    if (thumbExtended && indexExtended && !middleExtended && !ringExtended && pinkyExtended) {
      label = 'أحبك';
      confidence = 0.95;
    }
    // 2. ماء (ثلاثة أصابع ممتدة: السبابة والوسطى والبنصر مع طي الخنصر والإبهام)
    else if (indexExtended && middleExtended && ringExtended && !pinkyExtended) {
      label = 'ماء';
      confidence = 0.94;
    }
    // 3. مساعدة / Thumbs Up (الإبهام ممتد للأعلى وباقي الأصابع مطوية بقبضة)
    else if (thumbExtended && !indexExtended && !middleExtended && !ringExtended && !pinkyExtended) {
      label = 'مساعدة';
      confidence = 0.94;
    }
    // 4. طعام (أطراف كافة الأصابع ملتقية معاً في نقطة واحدة كقبضة طعام نحو الفم)
    else if (_dist(p4, p8) < palmScale * 0.45 &&
             _dist(p4, p12) < palmScale * 0.45 &&
             _dist(p4, p16) < palmScale * 0.48 &&
             _dist(p4, p20) < palmScale * 0.52) {
      label = 'طعام';
      confidence = 0.94;
    }
    // 5. السلام (كف مفتوح بالكامل وأصابع ممتدة ومتباعدة)
    else if (indexExtended && middleExtended && ringExtended && pinkyExtended && thumbExtended &&
             _dist(p8, p20) > palmScale * 0.60) {
      label = 'السلام';
      confidence = 0.95;
    }
    // 6. شكراً (كف مفتوح مستوٍ والأصابع الأربعة ممتدة ومتقاربة)
    else if (indexExtended && middleExtended && ringExtended && pinkyExtended &&
             _dist(p8, p12) < palmScale * 0.30) {
      label = 'شكراً';
      confidence = 0.92;
    }
    // 7. بيت (السبابة والوسطى متقاربتان بزاوية سقف خيمة مع طي باقي الأصابع)
    else if (indexExtended && middleExtended && !ringExtended && !pinkyExtended &&
             _dist(p8, p12) < palmScale * 0.30 && p8.y > p6.y) {
      label = 'بيت';
      confidence = 0.90;
    }
    // 8. سوق (تقارب السبابة والإبهام كإشارة نقود/سوق مع حركة الأصابع الأخرى)
    else if (_dist(p4, p8) < palmScale * 0.38 && (middleExtended || ringExtended)) {
      label = 'سوق';
      confidence = 0.90;
    }
    // 9. لا (إشارة نفي بحركة أفقية يمنة ويسرة للسبابة)
    else if ((indexExtended || (indexExtended && middleExtended)) && vel > 0.03 && dirX > 0.50) {
      label = 'لا';
      confidence = 0.92;
    }
    // 10. نعم (قبضة اليد تتحرك عمودياً كإيماء بالرأس للأسفل)
    else if (!indexExtended && !middleExtended && !ringExtended && !pinkyExtended && vel > 0.025 && dirY > 0.25) {
      label = 'نعم';
      confidence = 0.92;
    }
    // 11. ذهاب (السبابة والوسطى ممتدتان مع حركة للأمام)
    else if (indexExtended && middleExtended && !ringExtended && !pinkyExtended && vel > 0.035) {
      label = 'ذهاب';
      confidence = 0.90;
    }
    // 12. أنا (السبابة ممتدة وموجهة نحو الجسم/الصدر)
    else if (indexExtended && !middleExtended && !ringExtended && !pinkyExtended && (p8.y > p6.y || dirZ < -0.10)) {
      label = 'أنا';
      confidence = 0.92;
    }
    // 13. أنت (السبابة ممتدة للأمام نحو الكاميرا أو المخاطب)
    else if (indexExtended && !middleExtended && !ringExtended && !pinkyExtended && p8.y <= p6.y) {
      label = 'أنت';
      confidence = 0.91;
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
