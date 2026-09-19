import 'dart:math' as math;

/// بيانات وصفية خام تُحفظ لكل إطار يدخل الـ Ring Buffer
/// مفصولة تماماً عن مصفوفة الموديل (Model Tensor) لأغراض التشخيص وقياس الجودة
class FrameMetadata {
  final int frameId;
  final DateTime timestamp;

  // عدد النقاط الخام الحقيقية المكتشفة لكل جزء (قبل أي تعويض)
  final int rightHandRawCount; // 0..21
  final int leftHandRawCount; // 0..21
  final int lipsRawCount; // 0..19
  final int bodyRawCount; // 0..25

  // الإجمالي الخام والمعوض
  final int rawValidPoints; // 0..86 (مجموع النقاط الأربعة الحقيقية)
  final int imputedPoints; // 0..86 (النقاط المعوضة في الإطار)

  // سلامة الأرقام
  final int nanCount;
  final int infCount;

  // مصادر التعويض
  final bool rightHandImputed;
  final bool leftHandImputed;
  final bool lipsImputed;
  final bool bodyImputed;

  const FrameMetadata({
    required this.frameId,
    required this.timestamp,
    required this.rightHandRawCount,
    required this.leftHandRawCount,
    required this.lipsRawCount,
    required this.bodyRawCount,
    required this.rawValidPoints,
    required this.imputedPoints,
    this.nanCount = 0,
    this.infCount = 0,
    this.rightHandImputed = false,
    this.leftHandImputed = false,
    this.lipsImputed = false,
    this.bodyImputed = false,
  });

  bool get isRightHandRawValid => rightHandRawCount == 21;
  bool get isLeftHandRawValid => leftHandRawCount == 21;
  bool get isLipsRawValid => lipsRawCount == 19;
  bool get isBodyRawValid => bodyRawCount == 25;

  bool get hasAtLeastOneHand => isRightHandRawValid || isLeftHandRawValid;
  bool get hasBothHands => isRightHandRawValid && isLeftHandRawValid;
  bool get hasNoHands => rightHandRawCount == 0 && leftHandRawCount == 0;
  bool get isFullyRawComplete => rawValidPoints == 86;

  /// نسخة احتياطية افتراضية في حال عدم توفر الميتاداتا
  factory FrameMetadata.fromCounts({
    required int frameId,
    required DateTime timestamp,
    int rawDetectedCount = 86,
    int imputedCount = 0,
    int rh = 21,
    int lh = 21,
    int lips = 19,
    int body = 25,
    int nanCount = 0,
    int infCount = 0,
  }) {
    return FrameMetadata(
      frameId: frameId,
      timestamp: timestamp,
      rightHandRawCount: rh,
      leftHandRawCount: lh,
      lipsRawCount: lips,
      bodyRawCount: body,
      rawValidPoints: rawDetectedCount,
      imputedPoints: imputedCount,
      nanCount: nanCount,
      infCount: infCount,
    );
  }
}

/// تقرير شامل لجودة تسلسل الـ 128 إطاراً
class SequenceQualityReport {
  final DateTime capturedAt;
  final int frameCount;
  final int capacity;

  // 1. جودة البيانات الخام (Data Completeness)
  final int totalRawValidPoints;
  final int totalImputedPoints;
  final int totalPossiblePoints; // 128 * 86 = 11,008
  final double rawCoveragePercent; // Sequence Data Quality %
  final double imputationPercent;

  // 2. تغطية اليد اليمنى
  final int rhValidFrames;
  final double rhCoveragePercent;
  final int rhInitialMissing;
  final int rhLongestMissingRun;

  // 3. تغطية اليد اليسرى
  final int lhValidFrames;
  final double lhCoveragePercent;
  final int lhInitialMissing;
  final int lhLongestMissingRun;

  // 4. تغطية الشفاه
  final int lipsValidFrames;
  final double lipsCoveragePercent;
  final int lipsInitialMissing;
  final int lipsLongestMissingRun;

  // 5. تغطية الجسم
  final int bodyValidFrames;
  final double bodyCoveragePercent;
  final int bodyInitialMissing;
  final int bodyLongestMissingRun;

  // 6. توفر الأيدي (Hand Availability)
  final int atLeastOneHandFrames;
  final double atLeastOneHandPercent;
  final int bothHandsFrames;
  final double bothHandsPercent;
  final int noHandsFrames;
  final double noHandsPercent;

  // 7. الإطارات المكتملة خام 86/86
  final int fullRawFrames;
  final double fullRawPercent;

  // 8. التحقق الرياضي والزمني
  final int totalNanCount;
  final int totalInfCount;
  final int duplicateCount;
  final bool isChronologicalOrder;
  final double averageFrameIntervalMs;
  final double minFrameIntervalMs;
  final double maxFrameGapMs;

  const SequenceQualityReport({
    required this.capturedAt,
    required this.frameCount,
    required this.capacity,
    required this.totalRawValidPoints,
    required this.totalImputedPoints,
    required this.totalPossiblePoints,
    required this.rawCoveragePercent,
    required this.imputationPercent,
    required this.rhValidFrames,
    required this.rhCoveragePercent,
    required this.rhInitialMissing,
    required this.rhLongestMissingRun,
    required this.lhValidFrames,
    required this.lhCoveragePercent,
    required this.lhInitialMissing,
    required this.lhLongestMissingRun,
    required this.lipsValidFrames,
    required this.lipsCoveragePercent,
    required this.lipsInitialMissing,
    required this.lipsLongestMissingRun,
    required this.bodyValidFrames,
    required this.bodyCoveragePercent,
    required this.bodyInitialMissing,
    required this.bodyLongestMissingRun,
    required this.atLeastOneHandFrames,
    required this.atLeastOneHandPercent,
    required this.bothHandsFrames,
    required this.bothHandsPercent,
    required this.noHandsFrames,
    required this.noHandsPercent,
    required this.fullRawFrames,
    required this.fullRawPercent,
    required this.totalNanCount,
    required this.totalInfCount,
    required this.duplicateCount,
    required this.isChronologicalOrder,
    required this.averageFrameIntervalMs,
    required this.minFrameIntervalMs,
    required this.maxFrameGapMs,
  });

  /// إنشاء النص المنسق المطابق حرفياً لمتطلبات النسخ في الحافظة
  String toClipboardReportText() {
    final dateStr = capturedAt.toIso8601String().replaceFirst('T', ' ').split('.').first;

    return '''
================================
ISHARA SEQUENCE QUALITY REPORT
================================

Captured At:
$dateStr

Buffer:
$frameCount/$capacity

Sequence Shape:
[$frameCount,86,2]

Model Shape:
[1,$capacity,86,2]

--------------------------------

SEQUENCE DATA QUALITY:
${rawCoveragePercent.toStringAsFixed(2)} %

Metric:
Raw Keypoint Coverage

Raw valid points:
$totalRawValidPoints / $totalPossiblePoints

Imputed points:
$totalImputedPoints / $totalPossiblePoints

Imputation:
${imputationPercent.toStringAsFixed(2)} %

--------------------------------

RIGHT HAND

Valid frames:
$rhValidFrames / $frameCount

Coverage:
${rhCoveragePercent.toStringAsFixed(2)} %

Initial missing:
$rhInitialMissing

Longest missing run:
$rhLongestMissingRun frames

--------------------------------

LEFT HAND

Valid frames:
$lhValidFrames / $frameCount

Coverage:
${lhCoveragePercent.toStringAsFixed(2)} %

Initial missing:
$lhInitialMissing

Longest missing run:
$lhLongestMissingRun frames

--------------------------------

LIPS

Valid frames:
$lipsValidFrames / $frameCount

Coverage:
${lipsCoveragePercent.toStringAsFixed(2)} %

Initial missing:
$lipsInitialMissing

Longest missing run:
$lipsLongestMissingRun frames

--------------------------------

BODY

Valid frames:
$bodyValidFrames / $frameCount

Coverage:
${bodyCoveragePercent.toStringAsFixed(2)} %

Initial missing:
$bodyInitialMissing

Longest missing run:
$bodyLongestMissingRun frames

--------------------------------

HAND AVAILABILITY

At least one hand:
$atLeastOneHandFrames / $frameCount
${atLeastOneHandPercent.toStringAsFixed(2)} %

Both hands:
$bothHandsFrames / $frameCount
${bothHandsPercent.toStringAsFixed(2)} %

No hands:
$noHandsFrames / $frameCount
${noHandsPercent.toStringAsFixed(2)} %

--------------------------------

FULL RAW FRAMES:

$fullRawFrames / $frameCount
${fullRawPercent.toStringAsFixed(2)} %

--------------------------------

VALIDATION

NaN:
$totalNanCount

Infinity:
$totalInfCount

Duplicates:
$duplicateCount

Chronological order:
${isChronologicalOrder ? 'PASS' : 'FAIL'}

Average frame interval:
${averageFrameIntervalMs.round()} ms

Maximum frame gap:
${maxFrameGapMs.round()} ms

--------------------------------

QUALITY NOTES

This percentage represents RAW keypoint
data completeness.

It is NOT model accuracy.

No inference was executed.

================================
'''.trim();
  }
}

/// IsharaSequenceQualityAnalyzer
/// محلل جودة التسلسل لآخر 128 إطاراً في الـ Ring Buffer
class IsharaSequenceQualityAnalyzer {
  static const int pointsPerFrame = 86;

  /// تحليل قائمة إطارات مرتبة زمنياً Oldest -> Newest
  static SequenceQualityReport analyzeFrames({
    required List<FrameMetadata> metadataList,
    int capacity = 128,
    DateTime? captureTime,
  }) {
    final now = captureTime ?? DateTime.now();
    final count = metadataList.length;

    if (count == 0) {
      return SequenceQualityReport(
        capturedAt: now,
        frameCount: 0,
        capacity: capacity,
        totalRawValidPoints: 0,
        totalImputedPoints: 0,
        totalPossiblePoints: capacity * pointsPerFrame,
        rawCoveragePercent: 0.0,
        imputationPercent: 0.0,
        rhValidFrames: 0,
        rhCoveragePercent: 0.0,
        rhInitialMissing: 0,
        rhLongestMissingRun: 0,
        lhValidFrames: 0,
        lhCoveragePercent: 0.0,
        lhInitialMissing: 0,
        lhLongestMissingRun: 0,
        lipsValidFrames: 0,
        lipsCoveragePercent: 0.0,
        lipsInitialMissing: 0,
        lipsLongestMissingRun: 0,
        bodyValidFrames: 0,
        bodyCoveragePercent: 0.0,
        bodyInitialMissing: 0,
        bodyLongestMissingRun: 0,
        atLeastOneHandFrames: 0,
        atLeastOneHandPercent: 0.0,
        bothHandsFrames: 0,
        bothHandsPercent: 0.0,
        noHandsFrames: 0,
        noHandsPercent: 0.0,
        fullRawFrames: 0,
        fullRawPercent: 0.0,
        totalNanCount: 0,
        totalInfCount: 0,
        duplicateCount: 0,
        isChronologicalOrder: true,
        averageFrameIntervalMs: 0.0,
        minFrameIntervalMs: 0.0,
        maxFrameGapMs: 0.0,
      );
    }

    final totalPossible = count * pointsPerFrame;

    int totalRawValid = 0;
    int totalImputed = 0;

    int rhValid = 0;
    int lhValid = 0;
    int lipsValid = 0;
    int bodyValid = 0;

    int atLeastOneHand = 0;
    int bothHands = 0;
    int noHands = 0;
    int fullRaw = 0;

    int totalNan = 0;
    int totalInf = 0;

    // Initial missing runs (frames from index 0 until first true)
    int rhInitialMissing = count;
    int lhInitialMissing = count;
    int lipsInitialMissing = count;
    int bodyInitialMissing = count;

    bool rhFound = false;
    bool lhFound = false;
    bool lipsFound = false;
    bool bodyFound = false;

    // Consecutive missing runs
    int currentRhMissing = 0;
    int maxRhMissing = 0;

    int currentLhMissing = 0;
    int maxLhMissing = 0;

    int currentLipsMissing = 0;
    int maxLipsMissing = 0;

    int currentBodyMissing = 0;
    int maxBodyMissing = 0;

    for (int i = 0; i < count; i++) {
      final meta = metadataList[i];

      totalRawValid += meta.rawValidPoints;
      totalImputed += meta.imputedPoints;
      totalNan += meta.nanCount;
      totalInf += meta.infCount;

      // 1. Right Hand
      if (meta.isRightHandRawValid) {
        rhValid++;
        if (!rhFound) {
          rhInitialMissing = i;
          rhFound = true;
        }
        currentRhMissing = 0;
      } else {
        currentRhMissing++;
        if (currentRhMissing > maxRhMissing) {
          maxRhMissing = currentRhMissing;
        }
      }

      // 2. Left Hand
      if (meta.isLeftHandRawValid) {
        lhValid++;
        if (!lhFound) {
          lhInitialMissing = i;
          lhFound = true;
        }
        currentLhMissing = 0;
      } else {
        currentLhMissing++;
        if (currentLhMissing > maxLhMissing) {
          maxLhMissing = currentLhMissing;
        }
      }

      // 3. Lips
      if (meta.isLipsRawValid) {
        lipsValid++;
        if (!lipsFound) {
          lipsInitialMissing = i;
          lipsFound = true;
        }
        currentLipsMissing = 0;
      } else {
        currentLipsMissing++;
        if (currentLipsMissing > maxLipsMissing) {
          maxLipsMissing = currentLipsMissing;
        }
      }

      // 4. Body
      if (meta.isBodyRawValid) {
        bodyValid++;
        if (!bodyFound) {
          bodyInitialMissing = i;
          bodyFound = true;
        }
        currentBodyMissing = 0;
      } else {
        currentBodyMissing++;
        if (currentBodyMissing > maxBodyMissing) {
          maxBodyMissing = currentBodyMissing;
        }
      }

      // 5. Hand Availability
      if (meta.hasAtLeastOneHand) {
        atLeastOneHand++;
      }
      if (meta.hasBothHands) {
        bothHands++;
      }
      if (meta.hasNoHands) {
        noHands++;
      }

      // 6. Full Raw Complete
      if (meta.isFullyRawComplete) {
        fullRaw++;
      }
    }

    // النسب المئوية
    final rawCoveragePercent = totalPossible > 0 ? (totalRawValid / totalPossible) * 100.0 : 0.0;
    final imputationPercent = totalPossible > 0 ? (totalImputed / totalPossible) * 100.0 : 0.0;

    final rhCoveragePercent = (rhValid / count) * 100.0;
    final lhCoveragePercent = (lhValid / count) * 100.0;
    final lipsCoveragePercent = (lipsValid / count) * 100.0;
    final bodyCoveragePercent = (bodyValid / count) * 100.0;

    final atLeastOneHandPercent = (atLeastOneHand / count) * 100.0;
    final bothHandsPercent = (bothHands / count) * 100.0;
    final noHandsPercent = (noHands / count) * 100.0;
    final fullRawPercent = (fullRaw / count) * 100.0;

    // 7. حساب الفواصل الزمنية والترتيب الزمني والتكرار
    bool isChronological = true;
    int duplicateCount = 0;
    final List<double> intervals = [];

    for (int i = 1; i < count; i++) {
      final prev = metadataList[i - 1];
      final curr = metadataList[i];

      final diffMs = curr.timestamp.difference(prev.timestamp).inMicroseconds / 1000.0;

      if (diffMs <= 0 || curr.frameId <= prev.frameId) {
        if (diffMs == 0 || curr.frameId == prev.frameId) {
          duplicateCount++;
        } else {
          isChronological = false; // انعكاس زمني
        }
      }

      intervals.add(diffMs > 0 ? diffMs : 0.0);
    }

    double avgIntervalMs = 0.0;
    double minIntervalMs = 0.0;
    double maxGapMs = 0.0;

    if (intervals.isNotEmpty) {
      final sum = intervals.reduce((a, b) => a + b);
      avgIntervalMs = sum / intervals.length;
      minIntervalMs = intervals.reduce(math.min);
      maxGapMs = intervals.reduce(math.max);
    }

    return SequenceQualityReport(
      capturedAt: now,
      frameCount: count,
      capacity: capacity,
      totalRawValidPoints: totalRawValid,
      totalImputedPoints: totalImputed,
      totalPossiblePoints: totalPossible,
      rawCoveragePercent: rawCoveragePercent,
      imputationPercent: imputationPercent,
      rhValidFrames: rhValid,
      rhCoveragePercent: rhCoveragePercent,
      rhInitialMissing: rhInitialMissing,
      rhLongestMissingRun: maxRhMissing,
      lhValidFrames: lhValid,
      lhCoveragePercent: lhCoveragePercent,
      lhInitialMissing: lhInitialMissing,
      lhLongestMissingRun: maxLhMissing,
      lipsValidFrames: lipsValid,
      lipsCoveragePercent: lipsCoveragePercent,
      lipsInitialMissing: lipsInitialMissing,
      lipsLongestMissingRun: maxLipsMissing,
      bodyValidFrames: bodyValid,
      bodyCoveragePercent: bodyCoveragePercent,
      bodyInitialMissing: bodyInitialMissing,
      bodyLongestMissingRun: maxBodyMissing,
      atLeastOneHandFrames: atLeastOneHand,
      atLeastOneHandPercent: atLeastOneHandPercent,
      bothHandsFrames: bothHands,
      bothHandsPercent: bothHandsPercent,
      noHandsFrames: noHands,
      noHandsPercent: noHandsPercent,
      fullRawFrames: fullRaw,
      fullRawPercent: fullRawPercent,
      totalNanCount: totalNan,
      totalInfCount: totalInf,
      duplicateCount: duplicateCount,
      isChronologicalOrder: isChronological,
      averageFrameIntervalMs: avgIntervalMs,
      minFrameIntervalMs: minIntervalMs,
      maxFrameGapMs: maxGapMs,
    );
  }
}
