import 'dart:math' as math;
import 'package:ishara/keypoints/ishara_keypoint_mapper.dart';

/// KeypointNormalizer
/// التطبيع الرياضي الدقيق المطابق حرفياً لكود التدريب datasetv2.py / PoseDatasetV2
/// يطبّق نفس المعادلات على المجموعات الـ 4:
/// 1. اليد اليمنى (21 نقطة)
/// 2. اليد اليسرى (21 نقطة)
/// 3. الشفاه (19 نقطة)
/// 4. الجسم والرأس (25 نقطة)
class KeypointNormalizer {
  /// تطبيع مجموعة نقاط ثنائية الأبعاد [N, 2] حسب كود التدريب:
  /// 1. طرح أول نقطة (pose[0]) لجعل المرجع المعصم/الشفة/العنق
  /// 2. طرح أقل قيمة في كل محور لجعل البداية من الصفر
  /// 3. القسمة على أكبر قيمة في المحورين للتحجيم داخل صندوق 1x1
  /// 4. طرح المتوسط العام لكل العناصر
  /// 5. القسمة على القيمة المطلقة العظمى والضرب في 0.5 للتوسيط داخل [-0.5, 0.5]
  static List<List<double>> normalizeSubset(List<List<double>> subset) {
    final int n = subset.length;
    if (n == 0) return [];

    // التحقق هل جميع النقاط أصفار (غير مكتشفة)
    double sum = 0.0;
    for (int i = 0; i < n; i++) {
      sum += subset[i][0].abs() + subset[i][1].abs();
    }
    if (sum < 1e-6) {
      return List.generate(n, (_) => [0.0, 0.0]);
    }

    // إنشاء نسخة للتعديل
    final result = List.generate(n, (i) => [subset[i][0], subset[i][1]]);

    // 1. طرح أول نقطة pose[0]
    final double originX = result[0][0];
    final double originY = result[0][1];
    for (int i = 0; i < n; i++) {
      result[i][0] -= originX;
      result[i][1] -= originY;
    }

    // 2. طرح أقل قيمة في كل محور
    double minX = result[0][0];
    double minY = result[0][1];
    for (int i = 1; i < n; i++) {
      if (result[i][0] < minX) minX = result[i][0];
      if (result[i][1] < minY) minY = result[i][1];
    }
    for (int i = 0; i < n; i++) {
      result[i][0] -= minX;
      result[i][1] -= minY;
    }

    // 3. التحجيم في صندوق 1x1 (max_vals = np.max(pose, axis=0); pose /= max(max_vals))
    double maxX = result[0][0];
    double maxY = result[0][1];
    for (int i = 1; i < n; i++) {
      if (result[i][0] > maxX) maxX = result[i][0];
      if (result[i][1] > maxY) maxY = result[i][1];
    }
    final double maxCoord = math.max(maxX, maxY);
    if (maxCoord > 1e-7) {
      for (int i = 0; i < n; i++) {
        result[i][0] /= maxCoord;
        result[i][1] /= maxCoord;
      }
    }

    // 4. طرح المتوسط العام لجميع العناصر (np.mean(pose[:, :]))
    double totalVal = 0.0;
    for (int i = 0; i < n; i++) {
      totalVal += result[i][0] + result[i][1];
    }
    final double meanVal = totalVal / (2.0 * n);
    for (int i = 0; i < n; i++) {
      result[i][0] -= meanVal;
      result[i][1] -= meanVal;
    }

    // 5. القسمة على القيمة المطلقة العظمى والضرب في 0.5 (np.max(np.abs(pose[:, :])) * 0.5)
    double maxAbs = 0.0;
    for (int i = 0; i < n; i++) {
      final absX = result[i][0].abs();
      final absY = result[i][1].abs();
      if (absX > maxAbs) maxAbs = absX;
      if (absY > maxAbs) maxAbs = absY;
    }

    if (maxAbs > 1e-7) {
      for (int i = 0; i < n; i++) {
        result[i][0] = (result[i][0] / maxAbs) * 0.5;
        result[i][1] = (result[i][1] / maxAbs) * 0.5;
      }
    }

    return result;
  }

  /// تطبيع إطار كامل من 86 نقطة مع الحفاظ على النقاط المفقودة أو استراتيجية Carry-forward
  static KeypointFrame normalizeForModel(
    KeypointFrame rawFrame, {
    KeypointFrame? previousFrame,
  }) {
    final rawKeypoints = rawFrame.keypoints;
    final List<ModelKeypointInfo> normalizedList = [];

    // تقسيم المجموعات الـ 4
    List<List<double>> extractSubset(int start, int count) {
      final List<List<double>> sub = [];
      for (int i = 0; i < count; i++) {
        final kp = rawKeypoints[start + i];
        if (kp.isValid) {
          sub.add([kp.x!, kp.y!]);
        } else {
          // استراتيجية التدريب في datasetv2.py:
          // في حال فقدان نقاط اليد أو الجسم، يتم أخذ آخر إطار سليم (Carry-forward)
          // وإن لم يوجد، تُعطى 0.0
          if (previousFrame != null &&
              previousFrame.keypoints[start + i].isValid) {
            sub.add([
              previousFrame.keypoints[start + i].x!,
              previousFrame.keypoints[start + i].y!,
            ]);
          } else {
            sub.add([0.0, 0.0]);
          }
        }
      }
      return sub;
    }

    // 1. Right Hand [0..20]
    final rhRaw = extractSubset(0, IsharaKeypointMapper.numRightHand);
    final rhNorm = normalizeSubset(rhRaw);
    for (int i = 0; i < IsharaKeypointMapper.numRightHand; i++) {
      final isRawValid = rawKeypoints[i].isValid;
      normalizedList.add(rawKeypoints[i].copyWithCoordinates(
        isRawValid ? rhNorm[i][0] : null,
        isRawValid ? rhNorm[i][1] : null,
      ));
    }

    // 2. Left Hand [21..41]
    final lhRaw = extractSubset(21, IsharaKeypointMapper.numLeftHand);
    final lhNorm = normalizeSubset(lhRaw);
    for (int i = 0; i < IsharaKeypointMapper.numLeftHand; i++) {
      final isRawValid = rawKeypoints[21 + i].isValid;
      normalizedList.add(rawKeypoints[21 + i].copyWithCoordinates(
        isRawValid ? lhNorm[i][0] : null,
        isRawValid ? lhNorm[i][1] : null,
      ));
    }

    // 3. Face/Lips [42..60]
    final fcRaw = extractSubset(42, IsharaKeypointMapper.numLips);
    final fcNorm = normalizeSubset(fcRaw);
    for (int i = 0; i < IsharaKeypointMapper.numLips; i++) {
      final isRawValid = rawKeypoints[42 + i].isValid;
      normalizedList.add(rawKeypoints[42 + i].copyWithCoordinates(
        isRawValid ? fcNorm[i][0] : null,
        isRawValid ? fcNorm[i][1] : null,
      ));
    }

    // 4. Body/Head [61..85]
    final bdRaw = extractSubset(61, IsharaKeypointMapper.numBody);
    final bdNorm = normalizeSubset(bdRaw);
    for (int i = 0; i < IsharaKeypointMapper.numBody; i++) {
      final isRawValid = rawKeypoints[61 + i].isValid;
      normalizedList.add(rawKeypoints[61 + i].copyWithCoordinates(
        isRawValid ? bdNorm[i][0] : null,
        isRawValid ? bdNorm[i][1] : null,
      ));
    }

    return KeypointFrame(
      keypoints: normalizedList,
      timestamp: rawFrame.timestamp,
      isTrainingMappingVerified: rawFrame.isTrainingMappingVerified,
    );
  }
}
