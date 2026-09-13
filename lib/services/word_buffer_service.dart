import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/word_only_filter.dart';

/// مخزن الكلمات المؤكدة وإدارة حدود الجملة (Word Buffer & Sentence Boundary Manager)
///
/// ينفذ المتطلبات:
/// 10. Word Only Filter: قبول الكلمات الكاملة فقط واستبعاد أي حرف منفرد.
/// 13. Gloss Buffer: تجميع الكلمات المستقرة داخلياً دون عرض التموجات للمستخدم.
/// 14. Sentence Boundary: عدم تشغيل Gloss2Text إلا بعد توقف اليد، أو إشارة إنهاء، أو اختفاء اليد.
class WordBufferService extends ChangeNotifier {
  final List<String> _words = [];
  final List<SignPrediction> _predictionSequence = [];
  String? _lastEmittedWord;
  DateTime? _lastEmitTime;
  Timer? _sentenceTimeoutTimer;

  final Duration sentenceTimeout;
  final double minConfidence;
  final Duration debounceInterval;

  void Function(List<String> words, List<SignPrediction> sequence)? onSentenceReady;

  WordBufferService({
    this.sentenceTimeout = const Duration(milliseconds: AppConstants.sentencePauseDurationMs),
    this.minConfidence = AppConstants.minConfidence,
    this.debounceInterval = const Duration(milliseconds: 600),
  });

  List<String> get words => List.unmodifiable(_words);
  List<SignPrediction> get predictionSequence => List.unmodifiable(_predictionSequence);
  String get sentenceRaw => _words.join(' ');
  bool get isEmpty => _words.isEmpty;
  bool get isNotEmpty => _words.isNotEmpty;
  int get length => _words.length;

  /// إضافة كلمة مؤكدة جديدة قادمة من نموذج لغة الإشارة
  bool pushPrediction(SignPrediction prediction) {
    if (prediction.confidence < minConfidence) return false;

    // فحص مرشح الكلمات الصارم
    if (!WordOnlyFilter.isValidWord(prediction.label)) {
      return false;
    }

    final word = prediction.label.trim();
    final now = DateTime.now();

    // 1. فحص إشارة الإنهاء السريعة (Finish Gesture)
    if (word == 'إنهاء') {
      _triggerSentenceReadyNow();
      return true;
    }

    // 2. منع التكرار المتصل (Duplicate Suppression)
    if (_lastEmittedWord == word) {
      _resetSentenceTimeout();
      return false;
    }

    // 3. فحص الفاصل الزمني (Debounce Interval)
    if (_lastEmitTime != null && now.difference(_lastEmitTime!) < debounceInterval) {
      return false;
    }

    _lastEmittedWord = word;
    _lastEmitTime = now;

    // إضافة الكلمة وسجل التنبؤ للـ Buffer الداخلي
    _words.add(word);
    _predictionSequence.add(prediction);

    if (_words.length > 25) {
      _words.removeAt(0);
      _predictionSequence.removeAt(0);
    }

    notifyListeners();

    // 4. ضبط مؤقت اكتمال الجملة (Sentence Boundary Timeout)
    _resetSentenceTimeout();

    return true;
  }

  void _resetSentenceTimeout() {
    _sentenceTimeoutTimer?.cancel();
    _sentenceTimeoutTimer = Timer(sentenceTimeout, () {
      _triggerSentenceReadyNow();
    });
  }

  void _triggerSentenceReadyNow() {
    _sentenceTimeoutTimer?.cancel();
    if (_words.isNotEmpty && onSentenceReady != null) {
      final currentWords = List<String>.from(_words);
      final currentSequence = List<SignPrediction>.from(_predictionSequence);
      onSentenceReady!(currentWords, currentSequence);
    }
  }

  /// حذف آخر كلمة
  void deleteLastWord() {
    if (_words.isNotEmpty) {
      _words.removeLast();
      _predictionSequence.removeLast();
      _lastEmittedWord = _words.isNotEmpty ? _words.last : null;
      notifyListeners();
      _resetSentenceTimeout();
    }
  }

  /// مسح كافة الكلمات وإعادة التعيين
  void clear() {
    _sentenceTimeoutTimer?.cancel();
    _words.clear();
    _predictionSequence.clear();
    _lastEmittedWord = null;
    _lastEmitTime = null;
    notifyListeners();
  }

  /// إعادة تعيين اليد عند اختفائها من الكاميرا
  void resetCurrentHand() {
    _lastEmittedWord = null;
    // إذا كان هناك كلمات مسجلة واختفت اليد، نسرع استدعاء نهاية الجملة
    if (_words.isNotEmpty) {
      _sentenceTimeoutTimer?.cancel();
      _sentenceTimeoutTimer = Timer(const Duration(milliseconds: 700), () {
        _triggerSentenceReadyNow();
      });
    }
  }

  @override
  void dispose() {
    _sentenceTimeoutTimer?.cancel();
    super.dispose();
  }
}
