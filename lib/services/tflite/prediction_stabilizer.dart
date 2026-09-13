/// مُثبِّت التنبؤات وفلترة النتائج الوهمية (PredictionStabilizer)
/// يضمن عدم عرض أي تنبؤ عشوائي، ويمنع التكرار المتتالي لنفس الكلمة،
/// ويدير فترات التهدئة (Cooldown) وحالات غياب الإشارة.
class PredictionStabilizer {
  final double minimumConfidence;
  final int requiredStablePredictions;
  final Duration cooldownDuration;

  // الحالات الداخلية
  String? _lastCandidateGloss;
  int _candidateStreak = 0;
  String? _currentlyAcceptedGloss;
  DateTime? _lastAcceptedTime;
  final List<String> _glossSequence = [];

  PredictionStabilizer({
    this.minimumConfidence = 0.50,
    this.requiredStablePredictions = 2,
    this.cooldownDuration = const Duration(milliseconds: 900),
  });

  String? get currentlyAcceptedGloss => _currentlyAcceptedGloss;
  List<String> get glossSequence => List.unmodifiable(_glossSequence);

  /// معالجة مخرجات الاستنتاج الجديد
  /// [candidateGloss]: الكلمة الناتجة من CTC Greedy Decoder (أو null عند عدم وجود إشارة)
  /// [confidence]: نسبة ثقة الكلمة المستخرجة عبر Softmax
  /// [isSignActive]: هل تم كشف يد أو شخص يؤدي إشارة حقيقية
  String? processPrediction({
    required String? candidateGloss,
    required double confidence,
    required bool isSignActive,
  }) {
    // 1. إذا لم تكن هناك إشارة أو يد نشطة، نوقف الاستمرار
    if (!isSignActive || candidateGloss == null || candidateGloss.isEmpty) {
      _resetCandidateStreak();
      // إذا انقطعت الإشارة، نسمح بإعادة نفس الكلمة لاحقاً عند استئنافها
      return null;
    }

    // 2. التحقق من الحد الأدنى للثقة
    if (confidence < minimumConfidence) {
      _resetCandidateStreak();
      return null;
    }

    // 3. التحقق من فترة التهدئة إذا كانت نفس الكلمة السابقة لا تزال مستمرة
    final now = DateTime.now();
    if (_lastAcceptedTime != null &&
        now.difference(_lastAcceptedTime!) < cooldownDuration &&
        candidateGloss == _currentlyAcceptedGloss) {
      return null;
    }

    // 4. تتبع استقرار النتيجة عبر نوافذ استنتاج متعددة (Stable Windows)
    if (candidateGloss == _lastCandidateGloss) {
      _candidateStreak++;
    } else {
      _lastCandidateGloss = candidateGloss;
      _candidateStreak = 1;
    }

    // 5. اعتماد الكلمة فقط عند تحقيق عدد التكرارات المستقرة المطلوب
    if (_candidateStreak >= requiredStablePredictions) {
      // منع التكرار اللانهائي لنفس الكلمة
      if (candidateGloss != _currentlyAcceptedGloss) {
        _currentlyAcceptedGloss = candidateGloss;
        _lastAcceptedTime = now;
        _glossSequence.add(candidateGloss);
        _resetCandidateStreak();
        return candidateGloss;
      }
    }

    return null;
  }

  /// إعادة تعيين عند انتهاء الإشارة أو خروج الشخص
  void onSignEnded() {
    _resetCandidateStreak();
    _currentlyAcceptedGloss = null;
  }

  /// مسح كافة التنبؤات والذاكرة
  void clear() {
    _lastCandidateGloss = null;
    _candidateStreak = 0;
    _currentlyAcceptedGloss = null;
    _lastAcceptedTime = null;
    _glossSequence.clear();
  }

  void _resetCandidateStreak() {
    _lastCandidateGloss = null;
    _candidateStreak = 0;
  }
}
