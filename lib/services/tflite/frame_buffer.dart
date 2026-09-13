import 'package:flutter/foundation.dart';

/// مخزن إطارات زمني (Sliding Ring Buffer) يحتفظ بآخر 128 إطاراً
/// بحجم [128, 86, 2] لتشغيل نموذج CSLR Transformer
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

  /// فحص هل حان موعد تشغيل الاستنتاج الجديد عبر النافذة الانزلاقية (Sliding Window)
  bool shouldTriggerInference() {
    if (!isFull) return false;
    return _framesSinceLastInference >= inferenceStride;
  }

  /// إضافة إطار جديد بحجم [86, 2]
  /// [hasActivePerson]: علامة تدل على وجود يد أو شخص حقيقي لمنع النتائج الوهمية
  void addFrame(List<List<double>> frame, {required bool hasActivePerson}) {
    assert(
      frame.length == keypointsPerFrame,
      'Frame must contain exactly $keypointsPerFrame keypoints, got ${frame.length}',
    );

    // إضافة الإطار للذاكرة
    _buffer.add(frame);
    _activityMask.add(hasActivePerson);
    _framesSinceLastInference++;

    // إبقاء آخر 128 إطار فقط
    if (_buffer.length > requiredFrames) {
      _buffer.removeAt(0);
      _activityMask.removeAt(0);
    }
  }

  /// إرجاع مصفوفة الـ 128 إطاراً الحالية بالأبعاد [128, 86, 2]
  List<List<List<double>>>? getFrames() {
    if (!isFull) {
      debugPrint('[FrameBuffer] Buffer not full yet: ${_buffer.length}/$requiredFrames');
      return null;
    }
    // إرجاع نسخة غير قابلة للتعديل العرضي
    return List.generate(
      requiredFrames,
      (i) => List.generate(
        keypointsPerFrame,
        (j) => List<double>.from(_buffer[i][j]),
      ),
    );
  }

  /// تعليم أن الاستنتاج قد نُفِّذ لإعادة حساب الخطوات الانزلاقية
  void markInferenceExecuted() {
    _framesSinceLastInference = 0;
  }

  /// تفريغ المخزن بالكامل (عند تغيير الشاشة أو غياب الشخص)
  void clear() {
    _buffer.clear();
    _activityMask.clear();
    _framesSinceLastInference = 0;
  }
}
