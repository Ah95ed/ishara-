import 'dart:math';
import 'package:ishara/models/landmarks_model.dart';

/// كاشف ومستخرج الخصائص الرياضية والهندسية (Feature Engineering)
/// من نقاط MediaPipe الـ 21 لتتوافق بدقة مع ملف Dataset التدريب
class FeatureExtractor {
  static const int wrist = 0;
  static const int thumbTip = 4;
  static const int indexTip = 8;
  static const int middleTip = 12;
  static const int ringTip = 16;
  static const int pinkyTip = 20;

  /// استخراج مصفوفة الخصائص الكاملة (Features Vector)
  /// الترتيب: [Normalized Coordinates (63) + Distances (25) + Joint Angles (15) + Statistics (5)]
  static List<double> extractFeatures(HandLandmarks handLandmarks) {
    if (!handLandmarks.isValid) return [];
    final lm = handLandmarks.landmarks;

    final features = <double>[];

    // 1. التطبيع المكاني النسبي للمعصم (Normalized XYZ Coordinates - 63 features)
    final wristPt = lm[wrist];
    final middleMcp = lm[9];
    final handScale = _distance(wristPt, middleMcp).clamp(0.001, 10.0);

    // معالجة اليد اليسرى/اليمنى بانتظام عبر عكس المحور السيني لليد اليسرى
    final double handednessSign = handLandmarks.handedness == Handedness.left ? -1.0 : 1.0;

    for (int i = 0; i < 21; i++) {
      final pt = lm[i];
      features.add(((pt.x - wristPt.x) * handednessSign) / handScale);
      features.add((pt.y - wristPt.y) / handScale);
      features.add((pt.z - wristPt.z) / handScale);
    }

    // 2. المسافات الإقليدية النسبية (Distances - 25 features)
    // مسافات أطراف الأصابع عن المعصم (5)
    features.add(_distance(wristPt, lm[thumbTip]) / handScale);
    features.add(_distance(wristPt, lm[indexTip]) / handScale);
    features.add(_distance(wristPt, lm[middleTip]) / handScale);
    features.add(_distance(wristPt, lm[ringTip]) / handScale);
    features.add(_distance(wristPt, lm[pinkyTip]) / handScale);

    // المسافات البينية بين أطراف الأصابع (10 أزواج)
    final tips = [lm[thumbTip], lm[indexTip], lm[middleTip], lm[ringTip], lm[pinkyTip]];
    for (int i = 0; i < tips.length; i++) {
      for (int j = i + 1; j < tips.length; j++) {
        features.add(_distance(tips[i], tips[j]) / handScale);
      }
    }

    // أطوال عظام الأصابع (10)
    features.add(_distance(lm[1], lm[2]) / handScale);
    features.add(_distance(lm[2], lm[3]) / handScale);
    features.add(_distance(lm[5], lm[6]) / handScale);
    features.add(_distance(lm[6], lm[7]) / handScale);
    features.add(_distance(lm[9], lm[10]) / handScale);
    features.add(_distance(lm[10], lm[11]) / handScale);
    features.add(_distance(lm[13], lm[14]) / handScale);
    features.add(_distance(lm[14], lm[15]) / handScale);
    features.add(_distance(lm[17], lm[18]) / handScale);
    features.add(_distance(lm[18], lm[19]) / handScale);

    // 3. زوايا انثناء المفاصل (Joint Angles - 15 features)
    // الإبهام: زوايا عند النقطة 1، 2، 3
    features.add(_calculateAngle(lm[0], lm[1], lm[2]));
    features.add(_calculateAngle(lm[1], lm[2], lm[3]));
    features.add(_calculateAngle(lm[2], lm[3], lm[4]));

    // السبابة: زوايا عند النقطة 5، 6، 7
    features.add(_calculateAngle(lm[0], lm[5], lm[6]));
    features.add(_calculateAngle(lm[5], lm[6], lm[7]));
    features.add(_calculateAngle(lm[6], lm[7], lm[8]));

    // الوسطى: زوايا عند النقطة 9، 10، 11
    features.add(_calculateAngle(lm[0], lm[9], lm[10]));
    features.add(_calculateAngle(lm[9], lm[10], lm[11]));
    features.add(_calculateAngle(lm[10], lm[11], lm[12]));

    // البنصر: زوايا عند النقطة 13، 14، 15
    features.add(_calculateAngle(lm[0], lm[13], lm[14]));
    features.add(_calculateAngle(lm[13], lm[14], lm[15]));
    features.add(_calculateAngle(lm[14], lm[15], lm[16]));

    // الخنصر: زوايا عند النقطة 17، 18، 19
    features.add(_calculateAngle(lm[0], lm[17], lm[18]));
    features.add(_calculateAngle(lm[17], lm[18], lm[19]));
    features.add(_calculateAngle(lm[18], lm[19], lm[20]));

    // 4. المتوسطات والإحصاءات الحركية (Averages & Statistics - 5 features)
    double meanX = 0, meanY = 0, meanZ = 0;
    double minX = lm[0].x, maxX = lm[0].x;
    double minY = lm[0].y, maxY = lm[0].y;

    for (final pt in lm) {
      meanX += pt.x;
      meanY += pt.y;
      meanZ += pt.z;
      if (pt.x < minX) minX = pt.x;
      if (pt.x > maxX) maxX = pt.x;
      if (pt.y < minY) minY = pt.y;
      if (pt.y > maxY) maxY = pt.y;
    }

    features.add(meanX / 21.0);
    features.add(meanY / 21.0);
    features.add(meanZ / 21.0);
    features.add((maxX - minX) / handScale); // العرض النسبي
    features.add((maxY - minY) / handScale); // الارتفاع النسبي

    return features;
  }

  /// استخراج أسماء الأعمدة لتوليد أو مطابقة ملف CSV بدقة
  static List<String> getFeatureNames() {
    final names = <String>[];

    // أسماء الإحداثيات
    for (int i = 0; i < 21; i++) {
      names.add('norm_x_$i');
      names.add('norm_y_$i');
      names.add('norm_z_$i');
    }

    // أسماء مسافات أطراف الأصابع
    const fingerNames = ['thumb', 'index', 'middle', 'ring', 'pinky'];
    for (final f in fingerNames) {
      names.add('dist_wrist_${f}_tip');
    }

    // أسماء المسافات البينية
    for (int i = 0; i < fingerNames.length; i++) {
      for (int j = i + 1; j < fingerNames.length; j++) {
        names.add('dist_${fingerNames[i]}_${fingerNames[j]}');
      }
    }

    // أطوال العظام
    for (final f in fingerNames) {
      names.add('bone_length_${f}_1');
      names.add('bone_length_${f}_2');
    }

    // أسماء الزوايا
    for (final f in fingerNames) {
      names.add('angle_${f}_mcp');
      names.add('angle_${f}_pip');
      names.add('angle_${f}_dip');
    }

    // أسماء الإحصاءات
    names.add('mean_x');
    names.add('mean_y');
    names.add('mean_z');
    names.add('rel_hand_width');
    names.add('rel_hand_height');

    return names;
  }

  /// تحويل الخصائص إلى سطر CSV جاهز للتدريب أو المقارنة
  static String toCsvRow(HandLandmarks handLandmarks, {String? label}) {
    final values = extractFeatures(handLandmarks);
    if (values.isEmpty) return '';
    final row = values.map((v) => v.toStringAsFixed(5)).join(',');
    return label != null ? '$row,$label' : row;
  }

  static double _distance(HandLandmark a, HandLandmark b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return sqrt(dx * dx + dy * dy + dz * dz);
  }

  static double _calculateAngle(HandLandmark a, HandLandmark b, HandLandmark c) {
    // الزاوية عند النقطة b بين المتجهين ba و bc
    final baX = a.x - b.x;
    final baY = a.y - b.y;
    final baZ = a.z - b.z;

    final bcX = c.x - b.x;
    final bcY = c.y - b.y;
    final bcZ = c.z - b.z;

    final dotProduct = baX * bcX + baY * bcY + baZ * bcZ;
    final magBa = sqrt(baX * baX + baY * baY + baZ * baZ);
    final magBc = sqrt(bcX * bcX + bcY * bcY + bcZ * bcZ);

    if (magBa * magBc == 0) return 0.0;

    final cosAngle = (dotProduct / (magBa * magBc)).clamp(-1.0, 1.0);
    return acos(cosAngle); // الزاوية بالـ Radians
  }
}
