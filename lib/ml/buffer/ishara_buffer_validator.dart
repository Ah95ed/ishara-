import 'dart:typed_data';
import 'package:ishara/ml/preprocessing/ishara_normalizer.dart';

/// تقرير فحص سلامة وتناسق الـ Ring Buffer
class BufferValidationReport {
  final bool isValid;
  final int frameCount;
  final int capacity;
  final List<int> sequenceShape;
  final List<int> modelShape;
  final int nanCount;
  final int infCount;
  final int duplicateCount;
  final bool isChronologicallyOrdered;
  final bool deepCopyVerified;
  final String? failureReason;

  const BufferValidationReport({
    required this.isValid,
    required this.frameCount,
    required this.capacity,
    required this.sequenceShape,
    required this.modelShape,
    required this.nanCount,
    required this.infCount,
    required this.duplicateCount,
    required this.isChronologicallyOrdered,
    this.deepCopyVerified = true,
    this.failureReason,
  });
}

/// مدقق سلامة إطارات ومصفوفات الـ 128-Frame Buffer
class IsharaBufferValidator {
  static const int expectedKeypointCount = 86;
  static const int coordsPerPoint = 2;
  static const int valuesPerFrame = expectedKeypointCount * coordsPerPoint; // 172
  static const int expectedCapacity = 128;
  static const int totalModelValues = expectedCapacity * valuesPerFrame; // 22,016

  /// التحقق من صحة إطار فردي قبل إضافته للـ Buffer
  static String? validateSingleFrame(List<Point2D>? points) {
    if (points == null || points.isEmpty) {
      return 'EMPTY_FRAME';
    }
    if (points.length != expectedKeypointCount) {
      return 'INVALID_FRAME_SHAPE (expected $expectedKeypointCount, got ${points.length})';
    }

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.x.isNaN || p.y.isNaN) {
        return 'NAN_DETECTED at point $i';
      }
      if (p.x.isInfinite || p.y.isInfinite) {
        return 'INF_DETECTED at point $i';
      }
    }

    return null; // صالح وسليم 100%
  }

  /// فحص شريحة الـ Float32List الفردية للإطار (172 قيمة)
  static bool validateFrameData(Float32List data) {
    if (data.length != valuesPerFrame) return false;
    for (int i = 0; i < data.length; i++) {
      final v = data[i];
      if (v.isNaN || v.isInfinite) return false;
    }
    return true;
  }

  /// عد قيم NaN و Inf في مصفوفة مسطحة
  static ({int nanCount, int infCount}) countNanAndInf(Float32List data) {
    int nanCount = 0;
    int infCount = 0;
    for (int i = 0; i < data.length; i++) {
      final v = data[i];
      if (v.isNaN) {
        nanCount++;
      } else if (v.isInfinite) {
        infCount++;
      }
    }
    return (nanCount: nanCount, infCount: infCount);
  }

  /// التحقق الشامل من تسلسل الـ Snapshot قبل إرساله للموديل
  static BufferValidationReport validateSnapshot({
    required List<Float32List> frames,
    required List<int> sequenceIds,
    required int capacity,
  }) {
    final frameCount = frames.length;
    int totalNan = 0;
    int totalInf = 0;
    bool ordered = true;
    int duplicates = 0;

    // فحص الترتيب الزمني للأرقام التسلسلية وعدم وجود تكرار
    for (int i = 1; i < sequenceIds.length; i++) {
      if (sequenceIds[i] <= sequenceIds[i - 1]) {
        if (sequenceIds[i] == sequenceIds[i - 1]) {
          duplicates++;
        }
        ordered = false;
      }
    }

    // فحص كل إطار بحثاً عن أبعاد غير صحيحة أو NaN أو Inf
    for (int f = 0; f < frames.length; f++) {
      final frame = frames[f];
      if (frame.length != valuesPerFrame) {
        return BufferValidationReport(
          isValid: false,
          frameCount: frameCount,
          capacity: capacity,
          sequenceShape: [frameCount, expectedKeypointCount, coordsPerPoint],
          modelShape: [1, capacity, expectedKeypointCount, coordsPerPoint],
          nanCount: totalNan,
          infCount: totalInf,
          duplicateCount: duplicates,
          isChronologicallyOrdered: ordered,
          failureReason: 'Frame #$f invalid length: ${frame.length}',
        );
      }

      final counts = countNanAndInf(frame);
      totalNan += counts.nanCount;
      totalInf += counts.infCount;
    }

    final bool isValid = (totalNan == 0) &&
        (totalInf == 0) &&
        ordered &&
        (duplicates == 0) &&
        (frameCount <= capacity);

    return BufferValidationReport(
      isValid: isValid,
      frameCount: frameCount,
      capacity: capacity,
      sequenceShape: [frameCount, expectedKeypointCount, coordsPerPoint],
      modelShape: [1, capacity, expectedKeypointCount, coordsPerPoint],
      nanCount: totalNan,
      infCount: totalInf,
      duplicateCount: duplicates,
      isChronologicallyOrdered: ordered,
      failureReason: isValid ? null : 'Validation failed (nan: $totalNan, inf: $totalInf, ordered: $ordered)',
    );
  }
}
