import 'package:flutter/foundation.dart';

enum RecognitionStatus {
  noSign,
  uncertain,
  signDetected,
}

/// مُجمِّع تسلسل الإشارات المعتمدة (GlossAccumulator)
/// يتولى بناء جملة الـ Glosses تدريجياً:
/// ["انا"] -> ["انا", "اريد"] -> ["انا", "اريد", "مساعدة"]
/// مع قمع التكرارات اللحظية وإدارة فترات التهدئة (Cooldown) وحالات NO_SIGN / UNCERTAIN.
class GlossAccumulator extends ChangeNotifier {
  final Duration cooldownDuration;
  final int minStableHits;

  final List<String> _accumulatedGlosses = [];
  String? _currentGlossCandidate;
  int _candidateHitCount = 0;
  String? _lastEmittedGloss;
  DateTime? _lastEmittedTime;
  RecognitionStatus _status = RecognitionStatus.noSign;

  GlossAccumulator({
    this.cooldownDuration = const Duration(milliseconds: 1000),
    this.minStableHits = 2,
  });

  List<String> get accumulatedGlosses => List.unmodifiable(_accumulatedGlosses);
  String get fullSequenceText => _accumulatedGlosses.join(' ');
  String? get currentGlossCandidate => _currentGlossCandidate;
  RecognitionStatus get status => _status;
  bool get hasGlosses => _accumulatedGlosses.isNotEmpty;

  /// معالجة مخرجات الاستنتاج الجديد الوارد من CTC Decoder
  bool processDecodedGlosses(
    List<String> newGlosses, {
    required double confidence,
    required bool isSignActive,
  }) {
    // 1. حالة انعدام الحركة أو عدم وجود يد
    if (!isSignActive || newGlosses.isEmpty) {
      _status = RecognitionStatus.noSign;
      _candidateHitCount = 0;
      _currentGlossCandidate = null;
      notifyListeners();
      return false;
    }

    // 2. تصفية الكلمات المستبعدة
    final cleanGlosses = newGlosses
        .where((g) => g.isNotEmpty && g != '_' && g != 'blank' && g != '0')
        .toList();

    if (cleanGlosses.isEmpty) {
      _status = RecognitionStatus.noSign;
      return false;
    }

    // نأخذ الكلمة الأبرز في النافذة
    final candidate = cleanGlosses.join(' ').trim();
    _currentGlossCandidate = candidate;

    // 3. فحص الاستقرار عبر النوافذ المتعاقبة
    if (candidate == _lastEmittedGloss) {
      final now = DateTime.now();
      if (_lastEmittedTime != null && now.difference(_lastEmittedTime!) < cooldownDuration) {
        // قمع التكرار المستمر لنفس الإشارة أثناء بقاء اليد في نفس الوضعية
        _status = RecognitionStatus.uncertain;
        notifyListeners();
        return false;
      }
    }

    _candidateHitCount++;

    // 4. اعتماد الإشارة عند تحقيق الثبات المطلوب
    if (_candidateHitCount >= minStableHits) {
      // إضافة الكلمة للتسلسل
      if (candidate != _lastEmittedGloss) {
        _accumulatedGlosses.add(candidate);
        _lastEmittedGloss = candidate;
        _lastEmittedTime = DateTime.now();
        _status = RecognitionStatus.signDetected;
        _candidateHitCount = 0;
        notifyListeners();
        return true;
      }
    } else {
      _status = RecognitionStatus.uncertain;
      notifyListeners();
    }

    return false;
  }

  /// إشعار بانتهاء الإشارة أو عودة اليدين إلى وضع السكون
  void onSignEnded() {
    _currentGlossCandidate = null;
    _candidateHitCount = 0;
    _lastEmittedGloss = null; // يسمح بتكرار نفس الكلمة إذا قام بها المستخدم عمداً مرة ثانية
    _status = RecognitionStatus.noSign;
    notifyListeners();
  }

  /// مسح التسلسل بالكامل
  void clear() {
    _accumulatedGlosses.clear();
    _currentGlossCandidate = null;
    _candidateHitCount = 0;
    _lastEmittedGloss = null;
    _lastEmittedTime = null;
    _status = RecognitionStatus.noSign;
    notifyListeners();
  }
}
