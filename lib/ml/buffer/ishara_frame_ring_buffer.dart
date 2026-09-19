import 'dart:typed_data';
import 'package:ishara/ml/analyzer/ishara_sequence_quality_analyzer.dart';
import 'package:ishara/ml/buffer/ishara_buffer_validator.dart';
import 'package:ishara/ml/preprocessing/ishara_normalizer.dart';

/// حالات الـ 128-Frame Ring Buffer
enum RingBufferState {
  empty,
  filling,
  ready,
  paused,
}

extension RingBufferStateExt on RingBufferState {
  String get displayName {
    switch (this) {
      case RingBufferState.empty:
        return 'EMPTY';
      case RingBufferState.filling:
        return 'FILLING';
      case RingBufferState.ready:
        return 'READY';
      case RingBufferState.paused:
        return 'PAUSED';
    }
  }
}

/// تمثيل الإطار الواحد داخل الـ Buffer مع ضمان النسخ العميق (Deep Copy)
class IsharaBufferFrame {
  final int sequenceId;
  final DateTime timestamp;
  final Float32List data; // 172 floats = 86 keypoints * 2 coordinates
  final int rawDetectedCount;
  final int imputedCount;
  final bool isTrainingMatch;
  final FrameMetadata metadata;

  IsharaBufferFrame({
    required this.sequenceId,
    required this.timestamp,
    required Float32List data,
    required this.rawDetectedCount,
    required this.imputedCount,
    required this.isTrainingMatch,
    FrameMetadata? metadata,
  })  : data = Float32List.fromList(data),
        metadata = metadata ??
            FrameMetadata.fromCounts(
              frameId: sequenceId,
              timestamp: timestamp,
              rawDetectedCount: rawDetectedCount,
              imputedCount: imputedCount,
            );

  /// استنساخ عميق إضافي
  IsharaBufferFrame clone() {
    return IsharaBufferFrame(
      sequenceId: sequenceId,
      timestamp: timestamp,
      data: Float32List.fromList(data),
      rawDetectedCount: rawDetectedCount,
      imputedCount: imputedCount,
      isTrainingMatch: isTrainingMatch,
      metadata: metadata,
    );
  }

  /// تحويل البيانات المسطحة إلى مصفوفة [86, 2]
  List<List<double>> toKeypointMatrix() {
    final List<List<double>> matrix = [];
    for (int i = 0; i < 86; i++) {
      matrix.add([data[i * 2], data[i * 2 + 1]]);
    }
    return matrix;
  }
}

/// مصفوفة الإدخال الجاهزة للموديل [1, 128, 86, 2]
class ModelInputSequence {
  final Float32List flatData; // 1 * 128 * 86 * 2 = 22,016 floats
  final List<int> shape; // [1, 128, 86, 2]
  final int oldestFrameSequenceId;
  final int newestFrameSequenceId;
  final int nanCount;
  final int infCount;
  final bool hasBackwardFilledHands;
  final int frameCount;

  const ModelInputSequence({
    required this.flatData,
    required this.shape,
    required this.oldestFrameSequenceId,
    required this.newestFrameSequenceId,
    required this.nanCount,
    required this.infCount,
    required this.hasBackwardFilledHands,
    required this.frameCount,
  });

  /// تحويل التسلسل إلى مصفوفة متداخلة [1, 128, 86, 2]
  List<List<List<List<double>>>> toNestedTensor() {
    final List<List<List<double>>> sequence = [];
    int offset = 0;
    for (int f = 0; f < 128; f++) {
      final List<List<double>> frame = [];
      for (int k = 0; k < 86; k++) {
        frame.add([flatData[offset++], flatData[offset++]]);
      }
      sequence.add(frame);
    }
    return [sequence];
  }
}

/// تقرير حالة الـ Ring Buffer للعرض السريع في الواجهة
class RingBufferStatus {
  final int frameCount; // 0..128
  final int capacity; // 128
  final RingBufferState state;
  final int? latestFrameSequenceId;
  final int? oldestFrameSequenceId;
  final List<int> frameShape; // [86, 2]
  final List<int> sequenceShape; // [frameCount, 86, 2]
  final List<int> modelShape; // [1, 128, 86, 2]
  final int nanCount;
  final int infCount;
  final int duplicateCount;
  final int totalFramesReceived;
  final int totalFramesAdded;
  final int totalFramesSkippedNoPerson;
  final int duplicateFramesRejected;
  final int invalidFramesRejected;
  final bool isReady;
  final String stateDisplayName;
  final SequenceQualityReport? qualityReport;

  const RingBufferStatus({
    required this.frameCount,
    required this.capacity,
    required this.state,
    this.latestFrameSequenceId,
    this.oldestFrameSequenceId,
    required this.frameShape,
    required this.sequenceShape,
    required this.modelShape,
    required this.nanCount,
    required this.infCount,
    required this.duplicateCount,
    required this.totalFramesReceived,
    required this.totalFramesAdded,
    required this.totalFramesSkippedNoPerson,
    required this.duplicateFramesRejected,
    required this.invalidFramesRejected,
    required this.isReady,
    required this.stateDisplayName,
    this.qualityReport,
  });
}

/// IsharaFrameRingBuffer
/// Ring / Circular Buffer بسعة ثابتة 128 إطاراً:
/// - ترتيب زمني صارم (Oldest -> Newest).
/// - استبدال تلقائي لأقدم إطار عند الامتلاء دون أي reset.
/// - منع التكرار (Duplicate Rejection) عبر الطابع الزمني.
/// - إيقاف مؤقت عند غياب الشخص (Pause without Clear).
/// - عدم مشاركة مراجع الذاكرة (Deep Copy لكل Float32List).
/// - أمان غير متزامن (Thread/Async Safe via Processing Lock).
/// - Backward-Fill لليدين على نسخة الـ Snapshot فقط دون تعديل الـ Buffer الحي.
class IsharaFrameRingBuffer {
  static const int capacity = 128;
  static const int keypointCount = 86;
  static const int coordsPerPoint = 2;
  static const int valuesPerFrame = keypointCount * coordsPerPoint; // 172
  static const int totalModelValues = capacity * valuesPerFrame; // 22,016

  // ── الذاكرة الدائرية الداخلية ──
  final List<IsharaBufferFrame?> _slots = List<IsharaBufferFrame?>.filled(capacity, null);
  int _head = 0; // مؤشر الكتابة القادم
  int _count = 0; // عدد الإطارات الحالية (0..128)
  int _sequenceCounter = 0;
  DateTime? _lastAddedTimestamp;

  // ── قفل الأمان غير المتزامن ومؤشرات الحالة ──
  bool _isAddingFrame = false;
  bool _isPersonDetected = false;

  // ── عدادات التشخيص والمراقبة ──
  int _totalFramesReceived = 0;
  int _totalFramesAdded = 0;
  int _totalFramesSkippedNoPerson = 0;
  int _duplicateFramesRejected = 0;
  int _invalidFramesRejected = 0;

  // ── كاش تقرير الجودة لمنع تكرار الحساب على كل Frame ──
  SequenceQualityReport? _cachedQualityReport;
  DateTime? _lastQualityReportTime;

  // Getters للعدادات
  int get count => _count;
  bool get isReady => _count == capacity;
  int get totalFramesReceived => _totalFramesReceived;
  int get totalFramesAdded => _totalFramesAdded;
  int get totalFramesSkippedNoPerson => _totalFramesSkippedNoPerson;
  int get duplicateFramesRejected => _duplicateFramesRejected;
  int get invalidFramesRejected => _invalidFramesRejected;

  /// الحالة اللحظية للـ Buffer
  RingBufferState get state {
    if (!_isPersonDetected) {
      return RingBufferState.paused;
    }
    if (_count == 0) {
      return RingBufferState.empty;
    }
    if (_count < capacity) {
      return RingBufferState.filling;
    }
    return RingBufferState.ready;
  }

  /// إضافة إطار جديد إلى الـ Ring Buffer
  bool addFrame({
    required List<Point2D> normalizedPoints,
    required DateTime timestamp,
    required bool personPresent,
    int rawDetectedCount = 86,
    int imputedCount = 0,
    bool isTrainingMatch = true,
    FrameMetadata? metadata,
    int? frameId,
    int? rightHandRawCount,
    int? leftHandRawCount,
    int? lipsRawCount,
    int? bodyRawCount,
    int? nanCount,
    int? infCount,
  }) {
    // 1. قفل الأمان لمنع تداخل عمليات الإضافة المتزامنة
    if (_isAddingFrame) return false;
    _isAddingFrame = true;

    try {
      _totalFramesReceived++;
      _isPersonDetected = personPresent;

      // 2. إذا كان الشخص غير موجود: أوقف الإضافة دون مسح الـ Buffer
      if (!personPresent) {
        _totalFramesSkippedNoPerson++;
        return false;
      }

      // 3. منع إضافة نفس الإطار مرتين (Duplicate Timestamp Check)
      if (_lastAddedTimestamp != null && !timestamp.isAfter(_lastAddedTimestamp!)) {
        _duplicateFramesRejected++;
        return false;
      }

      // 4. التحقق من صحة وسلامة الإطار قبل الإضافة
      final error = IsharaBufferValidator.validateSingleFrame(normalizedPoints);
      if (error != null) {
        _invalidFramesRejected++;
        return false;
      }

      // 5. إنشاء Deep Copy للبيانات داخل Float32List (172 قيمة)
      final Float32List frameData = Float32List(valuesPerFrame);
      for (int i = 0; i < keypointCount; i++) {
        frameData[i * 2] = normalizedPoints[i].x.toDouble();
        frameData[i * 2 + 1] = normalizedPoints[i].y.toDouble();
      }

      _sequenceCounter++;

      final frameMeta = metadata ??
          FrameMetadata(
            frameId: frameId ?? _sequenceCounter,
            timestamp: timestamp,
            rightHandRawCount: rightHandRawCount ?? (rawDetectedCount >= 21 ? 21 : 0),
            leftHandRawCount: leftHandRawCount ?? (rawDetectedCount >= 42 ? 21 : 0),
            lipsRawCount: lipsRawCount ?? (rawDetectedCount >= 61 ? 19 : 0),
            bodyRawCount: bodyRawCount ?? (rawDetectedCount >= 86 ? 25 : 0),
            rawValidPoints: rawDetectedCount,
            imputedPoints: imputedCount,
            nanCount: nanCount ?? 0,
            infCount: infCount ?? 0,
          );

      final newFrame = IsharaBufferFrame(
        sequenceId: _sequenceCounter,
        timestamp: timestamp,
        data: frameData,
        rawDetectedCount: rawDetectedCount,
        imputedCount: imputedCount,
        isTrainingMatch: isTrainingMatch,
        metadata: frameMeta,
      );

      // 6. الكتابة داخل المؤشر الدائري
      _slots[_head] = newFrame;
      _head = (_head + 1) % capacity;

      if (_count < capacity) {
        _count++;
      }

      _lastAddedTimestamp = timestamp;
      _totalFramesAdded++;

      return true;
    } finally {
      _isAddingFrame = false;
    }
  }

  /// استرجاع الإطارات مرتبة زمنياً من الأقدم إلى الأحدث (Oldest -> Newest)
  List<IsharaBufferFrame> getChronologicalFrames() {
    final List<IsharaBufferFrame> frames = [];
    if (_count == 0) return frames;

    if (_count < capacity) {
      // لم يلتف الـ Buffer بعد: الإطارات من 0 إلى _count - 1
      for (int i = 0; i < _count; i++) {
        if (_slots[i] != null) {
          frames.add(_slots[i]!);
        }
      }
    } else {
      // الـ Buffer ممتلئ (128): _head يشير دائماً لأقدم إطار (الذي سيتم استبداله تالياً)
      for (int i = 0; i < capacity; i++) {
        final index = (_head + i) % capacity;
        if (_slots[index] != null) {
          frames.add(_slots[index]!);
        }
      }
    }

    return frames;
  }

  /// تطبيق Backward-Fill لليدين على نسخة الـ Snapshot فقط
  /// المنطق من datasetv2.py:
  /// من Frame 126 نزولاً إلى 0: إذا كان كامل اليد في الإطار أصفار، يتم نسخه من الإطار i+1
  /// خاص فقط بـ Right Hand و Left Hand، ولا يمس الشفاه أو الجسم.
  static void applyHandsBackwardFillToSnapshot(List<Float32List> snapshotFrames) {
    if (snapshotFrames.length < 2) return;

    // إحداثيات ومواقع اليدين في مصفوفة الـ Float32List (172 قيمة):
    // Right Hand: نقاط 0..20 = إحداثيات 0..41 (42 floats)
    // Left Hand: نقاط 21..41 = إحداثيات 42..83 (42 floats)
    const int rhStart = 0;
    const int rhLength = 21 * 2; // 42
    const int lhStart = 21 * 2; // 42
    const int lhLength = 21 * 2; // 42

    bool isGroupZeros(Float32List frame, int start, int length) {
      for (int i = start; i < start + length; i++) {
        if (frame[i].abs() > 1e-7) return false;
      }
      return true;
    }

    void copyGroup(Float32List src, Float32List dest, int start, int length) {
      for (int i = start; i < start + length; i++) {
        dest[i] = src[i];
      }
    }

    // المرور العكسي من نهاية الـ Snapshot إلى بدايته
    for (int i = snapshotFrames.length - 2; i >= 0; i--) {
      final current = snapshotFrames[i];
      final next = snapshotFrames[i + 1];

      // 1. Right Hand backward-fill
      if (isGroupZeros(current, rhStart, rhLength)) {
        copyGroup(next, current, rhStart, rhLength);
      }

      // 2. Left Hand backward-fill
      if (isGroupZeros(current, lhStart, lhLength)) {
        copyGroup(next, current, lhStart, lhLength);
      }
    }
  }

  /// بناء مصفوفة الإدخال للموديل [1, 128, 86, 2]
  /// يعمل فقط عند اكتمال الـ Buffer (128 إطاراً)، ويضمن النسخ العميق وتطبيق الـ Backward Fill
  ModelInputSequence? buildModelInput({bool applyHandsBackwardFill = true}) {
    if (_count < capacity) {
      return null; // الـ Buffer لم يكتمل بعد
    }

    // 1. استخراج الإطارات مرتبة زمنياً
    final chronological = getChronologicalFrames();
    if (chronological.length != capacity) return null;

    final oldestId = chronological.first.sequenceId;
    final newestId = chronological.last.sequenceId;

    // 2. استنساخ عميق للإطارات الـ 128 كشريحة مستقلة
    final List<Float32List> snapshotCopies = List.generate(
      capacity,
      (i) => Float32List.fromList(chronological[i].data),
      growable: false,
    );

    // 3. تطبيق Backward Fill لليدين على النسخة فقط إن طُلب
    if (applyHandsBackwardFill) {
      applyHandsBackwardFillToSnapshot(snapshotCopies);
    }

    // 4. تسطيح المصفوفة إلى [1, 128, 86, 2] = 22,016 قيمة
    final Float32List flatModelInput = Float32List(totalModelValues);
    int destOffset = 0;
    int nanCount = 0;
    int infCount = 0;

    for (int f = 0; f < capacity; f++) {
      final frame = snapshotCopies[f];
      for (int v = 0; v < valuesPerFrame; v++) {
        final val = frame[v];
        if (val.isNaN) nanCount++;
        if (val.isInfinite) infCount++;
        flatModelInput[destOffset++] = val;
      }
    }

    return ModelInputSequence(
      flatData: flatModelInput,
      shape: const [1, capacity, keypointCount, coordsPerPoint],
      oldestFrameSequenceId: oldestId,
      newestFrameSequenceId: newestId,
      nanCount: nanCount,
      infCount: infCount,
      hasBackwardFilledHands: applyHandsBackwardFill,
      frameCount: capacity,
    );
  }

  /// تحليل التسلسل الحالي واستخراج تقرير الجودة الشامل
  SequenceQualityReport analyzeCurrentSequence({DateTime? captureTime}) {
    final frames = getChronologicalFrames();
    final metadataList = frames.map((f) => f.metadata).toList();
    final report = IsharaSequenceQualityAnalyzer.analyzeFrames(
      metadataList: metadataList,
      capacity: capacity,
      captureTime: captureTime,
    );
    _cachedQualityReport = report;
    _lastQualityReportTime = captureTime ?? DateTime.now();
    return report;
  }

  /// الحصول على تقرير الحالة اللحظي للـ Buffer مع إمكانية تحديث تقرير الجودة
  RingBufferStatus getStatus({bool refreshQuality = false}) {
    final frames = getChronologicalFrames();
    final currentState = state;

    int nanCount = 0;
    int infCount = 0;

    if (frames.isNotEmpty) {
      final latest = frames.last.data;
      final counts = IsharaBufferValidator.countNanAndInf(latest);
      nanCount = counts.nanCount;
      infCount = counts.infCount;

      // تحديث تقرير الجودة دورياً (مرة كل 350ms أو عند الطلب) لمنع أي تأثير على الـ FPS
      final now = DateTime.now();
      if (refreshQuality ||
          _cachedQualityReport == null ||
          _lastQualityReportTime == null ||
          now.difference(_lastQualityReportTime!).inMilliseconds >= 350) {
        analyzeCurrentSequence(captureTime: now);
      }
    }

    return RingBufferStatus(
      frameCount: _count,
      capacity: capacity,
      state: currentState,
      latestFrameSequenceId: frames.isNotEmpty ? frames.last.sequenceId : null,
      oldestFrameSequenceId: frames.isNotEmpty ? frames.first.sequenceId : null,
      frameShape: const [keypointCount, coordsPerPoint],
      sequenceShape: [_count, keypointCount, coordsPerPoint],
      modelShape: const [1, capacity, keypointCount, coordsPerPoint],
      nanCount: nanCount,
      infCount: infCount,
      duplicateCount: _duplicateFramesRejected,
      totalFramesReceived: _totalFramesReceived,
      totalFramesAdded: _totalFramesAdded,
      totalFramesSkippedNoPerson: _totalFramesSkippedNoPerson,
      duplicateFramesRejected: _duplicateFramesRejected,
      invalidFramesRejected: _invalidFramesRejected,
      isReady: _count == capacity,
      stateDisplayName: currentState.displayName,
      qualityReport: _cachedQualityReport,
    );
  }

  /// تفريغ الـ Buffer (يستخدم فقط للاختبارات البرمجية الصريحة)
  void clearForTesting() {
    _slots.fillRange(0, capacity, null);
    _head = 0;
    _count = 0;
    _sequenceCounter = 0;
    _lastAddedTimestamp = null;
    _totalFramesReceived = 0;
    _totalFramesAdded = 0;
    _totalFramesSkippedNoPerson = 0;
    _duplicateFramesRejected = 0;
    _invalidFramesRejected = 0;
  }
}
