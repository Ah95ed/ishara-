import 'dart:collection';

/// مخزن تسلسلي زمني (Temporal Sequence Buffer)
/// يجمع الـ Features المتتالية من إطارات الكاميرا لتكوين مصفوفة حركة متتابعة (Sequence)
class TemporalBufferService {
  final int sequenceLength;
  final int featureDimension;
  final Queue<List<double>> _framesQueue = Queue<List<double>>();

  TemporalBufferService({
    this.sequenceLength = 30, // 30 إطاراً لتمثيل حركة الإشارة بالكامل
    this.featureDimension = 108, // عدد الخصائص المستخرجة لكل إطار
  });

  int get currentLength => _framesQueue.length;
  bool get isReady => _framesQueue.length >= sequenceLength;
  bool get isEmpty => _framesQueue.isEmpty;

  /// إضافة إطار جديد إلى الـ Buffer مع حذف الإطار الأقدم تلقائياً (Sliding Window)
  void addFrame(List<double> frameFeatures) {
    if (frameFeatures.isEmpty) return;

    // التأكد من تطابق حجم الخصائص أو تطبيعها للحجم الثابت
    List<double> normalizedFeatures;
    if (frameFeatures.length == featureDimension) {
      normalizedFeatures = List<double>.from(frameFeatures);
    } else if (frameFeatures.length > featureDimension) {
      normalizedFeatures = frameFeatures.sublist(0, featureDimension);
    } else {
      normalizedFeatures = List<double>.filled(featureDimension, 0.0);
      for (int i = 0; i < frameFeatures.length; i++) {
        normalizedFeatures[i] = frameFeatures[i];
      }
    }

    _framesQueue.addLast(normalizedFeatures);

    // الحفاظ على الطول الثابت ومنع تراكم الذاكرة
    while (_framesQueue.length > sequenceLength) {
      _framesQueue.removeFirst();
    }
  }

  /// إرجاع مصفوفة الحركة الثابتة [sequenceLength, featureDimension] الجاهزة لنموذج التدريب
  List<List<double>> getSequence() {
    if (_framesQueue.isEmpty) {
      return List.generate(
        sequenceLength,
        (_) => List<double>.filled(featureDimension, 0.0),
      );
    }

    final result = List<List<double>>.from(_framesQueue);

    // إذا كان عدد الإطارات أقل من المطلوب (في بداية الحركة)، نملأ الباقي بالإطار الأخير
    while (result.length < sequenceLength) {
      result.insert(0, List<double>.from(result.first));
    }

    return result;
  }

  /// تسطيح المصفوفة إلى متجه أحادي الأبعاد إن تطلب النموذج ذلك [sequenceLength * featureDimension]
  List<double> getFlattenedSequence() {
    final seq = getSequence();
    return seq.expand((frame) => frame).toList();
  }

  /// تفريغ الـ Buffer عند توقف اليد أو انتهاء الإشارة
  void clear() {
    _framesQueue.clear();
  }
}
