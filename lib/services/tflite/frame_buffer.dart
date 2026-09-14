/// مخزن إطارات زمني (Sliding Ring Buffer) ومعالج النوافذ الزمنية [128, 86, 2]
/// لنموذج CSLR Transformer (ishara_model.tflite)
class FrameBuffer {
  static const int requiredFrames = 128;
  static const int keypointsPerFrame = 86;
  static const int coordinatesPerKeypoint = 2;

  final List<List<List<double>>> _buffer = [];
  final List<bool> _activityMask = [];

  int _framesSinceLastInference = 0;
  final int inferenceStride;
  final double minActiveRatio;

  FrameBuffer({
    this.inferenceStride = 8,
    this.minActiveRatio = 0.35,
  });

  int get count => _buffer.length;
  bool get isFull => _buffer.length >= requiredFrames;
  int get framesSinceLastInference => _framesSinceLastInference;

  /// نسبة الإطارات النشطة (التي تحتوي على شخص ويدين حقيقيتين)
  double get activeRatio {
    if (_activityMask.isEmpty) return 0.0;
    final activeCount = _activityMask.where((a) => a).length;
    return activeCount / _activityMask.length;
  }

  /// فحص هل المخزن جاهز ويحتوي على حركة إشارة حقيقية كافية
  bool get hasValidSignActivity {
    return isFull && (activeRatio >= minActiveRatio);
  }

  /// فحص هل حان موعد تشغيل الاستنتاج
  bool shouldTriggerInference() {
    if (!isFull) return false;
    return _framesSinceLastInference >= inferenceStride;
  }

  /// إضافة إطار جديد بحجم [86, 2]
  void addFrame(List<List<double>> frame, {required bool hasActivePerson}) {
    assert(
      frame.length == keypointsPerFrame,
      'Frame must contain exactly $keypointsPerFrame keypoints, got ${frame.length}',
    );

    _buffer.add(List.generate(
      frame.length,
      (i) => List<double>.from(frame[i]),
    ));
    _activityMask.add(hasActivePerson);
    _framesSinceLastInference++;

    if (_buffer.length > requiredFrames) {
      _buffer.removeAt(0);
      _activityMask.removeAt(0);
    }
  }

  /// إرجاع مصفوفة الـ 128 إطاراً الحالية بالأبعاد [128, 86, 2]
  List<List<List<double>>>? getFrames() {
    if (!isFull) return null;
    return List.generate(
      requiredFrames,
      (i) => List.generate(
        keypointsPerFrame,
        (j) => List<double>.from(_buffer[i][j]),
      ),
    );
  }

  /// إعادة تشكيل وإعادة أخذ العينات الزمنية (Uniform Temporal Resampling)
  /// لأي شريحة إطارات ذات طول متغير T لتصبح بالضبط [128, 86, 2]
  /// بدون إدخال أصفار عشوائية أو تشويه ديناميكية الحركة (المتطلب 13)
  static List<List<List<double>>> padOrResampleTo128(
    List<List<List<double>>> inputFrames,
  ) {
    final int t = inputFrames.length;
    if (t == 0) {
      return List.generate(
        requiredFrames,
        (_) => List.generate(keypointsPerFrame, (_) => [0.0, 0.0]),
      );
    }
    if (t == requiredFrames) {
      return List.generate(
        requiredFrames,
        (i) => List.generate(
          keypointsPerFrame,
          (j) => List<double>.from(inputFrames[i][j]),
        ),
      );
    }

    // إذا كان الإطار واحداً فقط
    if (t == 1) {
      return List.generate(
        requiredFrames,
        (_) => List.generate(
          keypointsPerFrame,
          (j) => List<double>.from(inputFrames[0][j]),
        ),
      );
    }

    // إعادة أخذ عينات خطية مستمرة (Linear Temporal Resampling)
    final resampled = <List<List<double>>>[];
    for (int i = 0; i < requiredFrames; i++) {
      final double srcPos = i * (t - 1) / (requiredFrames - 1.0);
      final int baseIdx = srcPos.floor();
      final double frac = srcPos - baseIdx;

      if (baseIdx + 1 < t && frac > 1e-4) {
        final f0 = inputFrames[baseIdx];
        final f1 = inputFrames[baseIdx + 1];
        final interpolated = List.generate(keypointsPerFrame, (k) {
          final x = f0[k][0] * (1.0 - frac) + f1[k][0] * frac;
          final y = f0[k][1] * (1.0 - frac) + f1[k][1] * frac;
          return [x, y];
        });
        resampled.add(interpolated);
      } else {
        final clampedIdx = baseIdx.clamp(0, t - 1);
        resampled.add(List.generate(
          keypointsPerFrame,
          (k) => List<double>.from(inputFrames[clampedIdx][k]),
        ));
      }
    }

    return resampled;
  }

  /// إنشاء نافذة متداخلة ثانية (Window B) للتحقق الزمني المزدوج (المتطلب 16)
  static List<List<List<double>>> generateShiftedContextWindow(
    List<List<List<double>>> inputFrames, {
    int shiftFrames = 3,
  }) {
    if (inputFrames.length <= shiftFrames + 2) {
      return padOrResampleTo128(inputFrames);
    }
    // اقتطاع إزاحة طفيفة في البداية لاختبار استقرار التنبؤ
    final sub = inputFrames.sublist(shiftFrames);
    return padOrResampleTo128(sub);
  }

  void markInferenceExecuted() {
    _framesSinceLastInference = 0;
  }

  void clear() {
    _buffer.clear();
    _activityMask.clear();
    _framesSinceLastInference = 0;
  }
}
