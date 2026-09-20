import 'package:ishara/ml/analyzer/ishara_sequence_quality_analyzer.dart';

/// حالة ترشيح واستقرار الإشارة
enum CandidateState {
  none, // لا يوجد مرشح حالي
  candidate, // ظهرت الإشارة في نافذة واحدة
  stable, // تكررت الإشارة في نافذتين على الأقل من آخر 3 نوافذ (2/3)
  accepted, // تم قبول الإشارة رسمياً وتمريرها للمستخدم
}

/// لقطة مرشح نافذة واحدة من نوافذ الاستنتاج المتتالية
class WindowCandidate {
  final int windowIndex;
  final DateTime timestamp;
  final List<int> decodedIds;
  final List<String> glosses;
  final double sequenceConfidence;
  final double sequenceQuality;
  final double imputationPercent;

  const WindowCandidate({
    required this.windowIndex,
    required this.timestamp,
    required this.decodedIds,
    required this.glosses,
    required this.sequenceConfidence,
    required this.sequenceQuality,
    required this.imputationPercent,
  });

  bool matchesIds(List<int> other) {
    if (decodedIds.length != other.length) return false;
    for (int i = 0; i < decodedIds.length; i++) {
      if (decodedIds[i] != other[i]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'W$windowIndex: IDs=$decodedIds, Glosses=$glosses, Conf=${(sequenceConfidence * 100).toStringAsFixed(1)}%';
}

/// إعدادات معايير الجودة والاستقرار الزمني
class TemporalStabilityConfig {
  final double minSequenceQuality; // الافتراضي 85.0%
  final double maxImputation; // الافتراضي 15.0%
  final double minConfidence; // الافتراضي 0.40
  final int historyWindowSize; // عدد النوافذ للمقارنة (الافتراضي 3)
  final int requiredVotes; // عدد الأصوات للاستقرار (الافتراضي 2 من 3)

  const TemporalStabilityConfig({
    this.minSequenceQuality = 85.0,
    this.maxImputation = 15.0,
    this.minConfidence = 0.35,
    this.historyWindowSize = 3,
    this.requiredVotes = 2,
  });
}

/// نتيجة تقييم الاستقرار الزمني
class TemporalStabilityEvaluation {
  final CandidateState state;
  final bool isAccepted;
  final List<int> stableIds;
  final List<String> stableGlosses;
  final double sequenceConfidence;
  final int votes;
  final int totalWindows;
  final String reasonCode;
  final String reasonMessage;

  const TemporalStabilityEvaluation({
    required this.state,
    required this.isAccepted,
    required this.stableIds,
    required this.stableGlosses,
    required this.sequenceConfidence,
    required this.votes,
    required this.totalWindows,
    required this.reasonCode,
    required this.reasonMessage,
  });
}

/// IsharaTemporalStabilityTracker
/// متتبع الاستقرار الزمني ومنع التكرار لإشارات Ishara:
/// - يحتفظ بآخر 3 نوافذ استنتاج انزلاقية (Window 1, 2, 3)
/// - يقارن الـ Class IDs المشفرة (وليس النصوص لتجنب تباين التشكيل أو التهجئة)
/// - يطبق قاعدة التصويت 2 من 3 (2/3 Stability Voting)
/// - يفحص معايير الجودة (Sequence Quality Gate) مع اشتغال يد واحدة على الأقل
/// - يمنع تكرار نفس الكلمة داخل نفس مقطع الحركة (Sign Segment)
/// - يسمح بتكرار نفس الكلمة إذا بدأت إشارة جديدة مستقلة بعد انتهاء السابقة
class IsharaTemporalStabilityTracker {
  final TemporalStabilityConfig config;

  final List<WindowCandidate> _windowHistory = [];
  int _windowCounter = 0;

  // منع التكرار المرتبط برقم المقطع الحركي (Segment-scoped duplicate suppression)
  List<int>? _lastAcceptedIds;
  int? _lastAcceptedSegmentId;

  IsharaTemporalStabilityTracker({
    this.config = const TemporalStabilityConfig(),
  });

  List<WindowCandidate> get windowHistory => List.unmodifiable(_windowHistory);
  List<int>? get lastAcceptedIds => _lastAcceptedIds;

  /// تسجيل نافذة استنتاج جديدة وتقييم الاستقرار الزمني
  TemporalStabilityEvaluation registerInferenceWindow({
    required List<int> decodedIds,
    required List<String> glosses,
    required double sequenceConfidence,
    required SequenceQualityReport quality,
    required int currentSignSegmentId,
    required bool isSigningActive,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();
    _windowCounter++;

    final candidate = WindowCandidate(
      windowIndex: _windowCounter,
      timestamp: now,
      decodedIds: decodedIds,
      glosses: glosses,
      sequenceConfidence: sequenceConfidence,
      sequenceQuality: quality.rawCoveragePercent,
      imputationPercent: quality.imputationPercent,
    );

    // إضافة النافذة إلى السجل مع الحفاظ على حجم 3
    _windowHistory.add(candidate);
    if (_windowHistory.length > config.historyWindowSize) {
      _windowHistory.removeAt(0);
    }

    // 1. فحص نشاط الإشارة
    if (!isSigningActive) {
      return const TemporalStabilityEvaluation(
        state: CandidateState.none,
        isAccepted: false,
        stableIds: [],
        stableGlosses: [],
        sequenceConfidence: 0.0,
        votes: 0,
        totalWindows: 0,
        reasonCode: 'NO_SIGN_ACTIVITY',
        reasonMessage: 'User is idle; no active sign gesture',
      );
    }

    // 2. فحص مخرجات الـ CTC إذا كانت فارغة (فراغات فقط)
    if (decodedIds.isEmpty) {
      return const TemporalStabilityEvaluation(
        state: CandidateState.none,
        isAccepted: false,
        stableIds: [],
        stableGlosses: [],
        sequenceConfidence: 0.0,
        votes: 0,
        totalWindows: 0,
        reasonCode: 'EMPTY_CTC_SEQUENCE',
        reasonMessage: 'No non-blank tokens emitted by CTC',
      );
    }

    // 3. بوابة الجودة (Sequence Quality Gate)
    if (quality.rawCoveragePercent < config.minSequenceQuality) {
      return TemporalStabilityEvaluation(
        state: CandidateState.candidate,
        isAccepted: false,
        stableIds: decodedIds,
        stableGlosses: glosses,
        sequenceConfidence: sequenceConfidence,
        votes: 1,
        totalWindows: _windowHistory.length,
        reasonCode: 'SEQUENCE_QUALITY_LOW',
        reasonMessage:
            'Quality ${quality.rawCoveragePercent.toStringAsFixed(1)}% is below min ${config.minSequenceQuality}%',
      );
    }

    if (quality.imputationPercent > config.maxImputation) {
      return TemporalStabilityEvaluation(
        state: CandidateState.candidate,
        isAccepted: false,
        stableIds: decodedIds,
        stableGlosses: glosses,
        sequenceConfidence: sequenceConfidence,
        votes: 1,
        totalWindows: _windowHistory.length,
        reasonCode: 'IMPUTATION_TOO_HIGH',
        reasonMessage:
            'Imputation ${quality.imputationPercent.toStringAsFixed(1)}% exceeds max ${config.maxImputation}%',
      );
    }

    // فحص توفر يد واحدة على الأقل (لا نشترط كلتا اليدين)
    final bool hasHand = quality.rhCoveragePercent > 20.0 || quality.lhCoveragePercent > 20.0;
    if (!hasHand) {
      return TemporalStabilityEvaluation(
        state: CandidateState.candidate,
        isAccepted: false,
        stableIds: decodedIds,
        stableGlosses: glosses,
        sequenceConfidence: sequenceConfidence,
        votes: 1,
        totalWindows: _windowHistory.length,
        reasonCode: 'NO_HAND_PRESENT',
        reasonMessage: 'Neither right hand nor left hand has sufficient coverage',
      );
    }

    // 4. تصويت الاستقرار الزمني (2 من آخر 3 نوافذ)
    int votes = 0;
    for (final w in _windowHistory) {
      if (w.matchesIds(decodedIds)) {
        votes++;
      }
    }

    final bool isStable = votes >= config.requiredVotes;

    if (!isStable) {
      return TemporalStabilityEvaluation(
        state: CandidateState.candidate,
        isAccepted: false,
        stableIds: decodedIds,
        stableGlosses: glosses,
        sequenceConfidence: sequenceConfidence,
        votes: votes,
        totalWindows: _windowHistory.length,
        reasonCode: 'UNSTABLE',
        reasonMessage: 'Candidate has $votes/${config.historyWindowSize} votes; needs ${config.requiredVotes}',
      );
    }

    // 5. فحص الثقة التشخيصية للنموذج (Diagnostic Confidence Gate)
    if (sequenceConfidence < config.minConfidence) {
      return TemporalStabilityEvaluation(
        state: CandidateState.stable,
        isAccepted: false,
        stableIds: decodedIds,
        stableGlosses: glosses,
        sequenceConfidence: sequenceConfidence,
        votes: votes,
        totalWindows: _windowHistory.length,
        reasonCode: 'LOW_CONFIDENCE',
        reasonMessage:
            'Confidence ${(sequenceConfidence * 100).toStringAsFixed(1)}% is below threshold ${(config.minConfidence * 100).toStringAsFixed(1)}%',
      );
    }

    // 6. منع التكرار داخل نفس المقطع الحركي (Segment-scoped duplicate suppression)
    final bool isSameIds = _lastAcceptedIds != null && _listEquals(_lastAcceptedIds!, decodedIds);
    final bool isSameSegment = _lastAcceptedSegmentId == currentSignSegmentId;

    if (isSameIds && isSameSegment) {
      return TemporalStabilityEvaluation(
        state: CandidateState.stable,
        isAccepted: false,
        stableIds: decodedIds,
        stableGlosses: glosses,
        sequenceConfidence: sequenceConfidence,
        votes: votes,
        totalWindows: _windowHistory.length,
        reasonCode: 'DUPLICATE_IN_SEGMENT',
        reasonMessage: 'Sequence already accepted in the current sign segment',
      );
    }

    // 7. قبول المرشح رسمياً وتحديث حالة المقطع
    _lastAcceptedIds = List<int>.from(decodedIds);
    _lastAcceptedSegmentId = currentSignSegmentId;

    return TemporalStabilityEvaluation(
      state: CandidateState.accepted,
      isAccepted: true,
      stableIds: decodedIds,
      stableGlosses: glosses,
      sequenceConfidence: sequenceConfidence,
      votes: votes,
      totalWindows: _windowHistory.length,
      reasonCode: 'STABLE_AND_VALID',
      reasonMessage: 'Sequence passed quality, confidence, and 2/3 stability voting',
    );
  }

  /// إعادة تعيين سجل النوافذ
  void reset() {
    _windowHistory.clear();
    _windowCounter = 0;
    _lastAcceptedIds = null;
    _lastAcceptedSegmentId = null;
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
