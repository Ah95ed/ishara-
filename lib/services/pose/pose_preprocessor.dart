import 'dart:math';

/// كلاس المعالجة المسبقة والتطبيع (PosePreprocessor)
/// منقول حرفياً ومطابق 100% لخوارزميات التطبيع في datasetv2.py أثناء تدريب الموديل.
class PosePreprocessor {
  static const int numRightHandLandmarks = 21;
  static const int numLeftHandLandmarks = 21;
  static const int numLipLandmarks = 19;
  static const int numBodyLandmarks = 25;
  static const int totalKeypoints = 86;

  /// معرّفات نقاط الشفاه الخارجية المستخرجة والمفرزة من MediaPipe Face Mesh
  /// lipsUpperOuter = [61, 185, 40, 39, 37, 0, 267, 269, 270, 291]
  /// lipsLowerOuter = [146, 91, 181, 84, 17, 314, 405, 321, 375, 291]
  /// sorted unique: [0, 17, 37, 39, 40, 61, 84, 91, 146, 181, 185, 267, 269, 270, 291, 314, 321, 375, 405]
  static const List<int> lipMeshIndices = [
    0, 17, 37, 39, 40, 61, 84, 91, 146, 181,
    185, 267, 269, 270, 291, 314, 321, 375, 405
  ];

  // احتفاظ بآخر إطارات لتطبيق الاستمرارية الزمنية (Missing Landmark Carry-Forward)
  List<List<double>>? _lastRightHand;
  List<List<double>>? _lastLeftHand;
  List<List<double>>? _lastLips;
  List<List<double>>? _lastBody;

  /// إعادة تعيين الذاكرة المؤقتة للإطارات السابقة
  void reset() {
    _lastRightHand = null;
    _lastLeftHand = null;
    _lastLips = null;
    _lastBody = null;
  }

  /// معالجة إطار كامل وتجميع الـ 86 نقطة بالشكل [86][2]
  List<List<double>> processFrame({
    List<List<double>>? rawRightHand,
    List<List<double>>? rawLeftHand,
    List<List<double>>? rawLips,
    List<List<double>>? rawBody,
  }) {
    // 1. معالجة اليد اليمنى (21 نقطة)
    final rh = _resolveAndNormalize(
      rawPoints: rawRightHand,
      expectedCount: numRightHandLandmarks,
      lastPoints: _lastRightHand,
      onSave: (p) => _lastRightHand = p,
    );

    // 2. معالجة اليد اليسرى (21 نقطة)
    final lh = _resolveAndNormalize(
      rawPoints: rawLeftHand,
      expectedCount: numLeftHandLandmarks,
      lastPoints: _lastLeftHand,
      onSave: (p) => _lastLeftHand = p,
    );

    // 3. معالجة الشفاه (19 نقطة)
    final fc = _resolveAndNormalize(
      rawPoints: rawLips,
      expectedCount: numLipLandmarks,
      lastPoints: _lastLips,
      onSave: (p) => _lastLips = p,
    );

    // 4. معالجة الجزء العلوي للجسم (25 نقطة)
    final bd = _resolveAndNormalize(
      rawPoints: rawBody,
      expectedCount: numBodyLandmarks,
      lastPoints: _lastBody,
      onSave: (p) => _lastBody = p,
    );

    // دمج الأجزاء الأربعة بالترتيب المعتمد للتدريب:
    // right_joints (0..20) -> left_joints (21..41) -> face_joints (42..60) -> body_joints (61..85)
    final frame = <List<double>>[];
    frame.addAll(rh);
    frame.addAll(lh);
    frame.addAll(fc);
    frame.addAll(bd);

    assert(frame.length == totalKeypoints, 'Frame must have exactly 86 keypoints');
    return frame;
  }

  /// حل النقاط المفقودة وتطبيق التطبيع
  List<List<double>> _resolveAndNormalize({
    required List<List<double>>? rawPoints,
    required int expectedCount,
    required List<List<double>>? lastPoints,
    required void Function(List<List<double>>) onSave,
  }) {
    final bool hasData = rawPoints != null &&
        rawPoints.length == expectedCount &&
        !_isAllZeros(rawPoints);

    if (hasData) {
      // تطبيق نفس خوارزمية التطبيع المعتمدة في datasetv2.py
      final normalized = normalizeSubset(rawPoints);
      onSave(normalized);
      return normalized;
    } else if (lastPoints != null) {
      // استخدام نقاط الإطار السابق في حال الفقد المؤقت
      return _copyPoints(lastPoints);
    } else {
      // ملء أصفار في حال عدم التوفر مطلقاً
      return List.generate(expectedCount, (_) => [0.0, 0.0]);
    }
  }

  /// خوارزمية التطبيع الأساسية المنقولة نصياً من normalize() في datasetv2.py:
  ///
  /// ```python
  /// def normalize(self, pose):
  ///     pose[:,:] -= pose[0]
  ///     pose[:,:] -= np.min(pose, axis=0)
  ///     max_vals = np.max(pose, axis=0)
  ///     pose[:,:] /= max(max_vals)
  ///     pose[:,:] = pose[:,:] - np.mean(pose[:,:])
  ///     pose[:,:] = pose[:,:] / np.max(np.abs(pose[:,:]))
  ///     pose[:,:] = pose[:,:] * 0.5
  ///     return pose
  /// ```
  static List<List<double>> normalizeSubset(List<List<double>> inputPoints) {
    final int n = inputPoints.length;
    if (n == 0) return [];

    // إنشاء نسخة للعمل عليها دون تعديل الدخل الأصلي
    final pose = _copyPoints(inputPoints);

    // الخطوة 1: pose[:, :] -= pose[0]
    final double originX = pose[0][0];
    final double originY = pose[0][1];
    for (int i = 0; i < n; i++) {
      pose[i][0] -= originX;
      pose[i][1] -= originY;
    }

    // الخطوة 2: pose[:, :] -= np.min(pose, axis=0)
    double minX = pose[0][0];
    double minY = pose[0][1];
    for (int i = 1; i < n; i++) {
      if (pose[i][0] < minX) minX = pose[i][0];
      if (pose[i][1] < minY) minY = pose[i][1];
    }
    for (int i = 0; i < n; i++) {
      pose[i][0] -= minX;
      pose[i][1] -= minY;
    }

    // الخطوة 3: max_vals = np.max(pose, axis=0); pose[:, :] /= max(max_vals)
    double maxX = pose[0][0];
    double maxY = pose[0][1];
    for (int i = 1; i < n; i++) {
      if (pose[i][0] > maxX) maxX = pose[i][0];
      if (pose[i][1] > maxY) maxY = pose[i][1];
    }
    final double scale = max(maxX, maxY);
    if (scale > 1e-7) {
      for (int i = 0; i < n; i++) {
        pose[i][0] /= scale;
        pose[i][1] /= scale;
      }
    }

    // الخطوة 4: pose[:, :] = pose[:, :] - np.mean(pose[:, :])
    double sum = 0.0;
    for (int i = 0; i < n; i++) {
      sum += pose[i][0] + pose[i][1];
    }
    final double mean = sum / (n * 2.0);
    for (int i = 0; i < n; i++) {
      pose[i][0] -= mean;
      pose[i][1] -= mean;
    }

    // الخطوة 5: pose[:, :] = pose[:, :] / np.max(np.abs(pose[:, :]))
    double maxAbs = 0.0;
    for (int i = 0; i < n; i++) {
      final absX = pose[i][0].abs();
      final absY = pose[i][1].abs();
      if (absX > maxAbs) maxAbs = absX;
      if (absY > maxAbs) maxAbs = absY;
    }
    if (maxAbs > 1e-7) {
      for (int i = 0; i < n; i++) {
        pose[i][0] /= maxAbs;
        pose[i][1] /= maxAbs;
      }
    }

    // الخطوة 6: pose[:, :] = pose[:, :] * 0.5
    for (int i = 0; i < n; i++) {
      pose[i][0] *= 0.5;
      pose[i][1] *= 0.5;
    }

    return pose;
  }

  static bool _isAllZeros(List<List<double>> points) {
    for (final p in points) {
      if (p[0].abs() > 1e-6 || p[1].abs() > 1e-6) {
        return false;
      }
    }
    return true;
  }

  static List<List<double>> _copyPoints(List<List<double>> src) {
    return List.generate(src.length, (i) => [src[i][0], src[i][1]]);
  }
}
