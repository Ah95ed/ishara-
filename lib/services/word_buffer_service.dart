import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ishara/models/sign_prediction_model.dart';

/// مخزن الكلمات المؤكدة وإدارة الجملة (Word Buffer & Sentence Manager)
/// يمنع تكرار الكلمات المتصلة، ويتحكم في مؤقت اكتمال الجملة (Sentence Timeout)
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
    this.sentenceTimeout = const Duration(milliseconds: 1500),
    this.minConfidence = 0.85,
    this.debounceInterval = const Duration(milliseconds: 800),
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

    final word = prediction.label.trim();
    if (word.isEmpty) return false;

    final now = DateTime.now();

    // 1. منع التكرار المتصل (Duplicate Prevention): لا نكرر نفس الكلمة إذا استمرت الإشارة
    if (_lastEmittedWord == word) {
      // إعادة ضبط مؤقت الجملة طالما أن المستخدم لا يزال يشير
      _resetSentenceTimeout();
      return false;
    }

    // 2. فحص الفاصل الزمني (Debounce Interval)
    if (_lastEmitTime != null && now.difference(_lastEmitTime!) < debounceInterval) {
      return false;
    }

    _lastEmittedWord = word;
    _lastEmitTime = now;

    // إضافة الكلمة وسجل التنبؤ
    _words.add(word);
    _predictionSequence.add(prediction);

    if (_words.length > 25) {
      _words.removeAt(0);
      _predictionSequence.removeAt(0);
    }

    notifyListeners();

    // 3. تشغيل مؤقت اكتمال الجملة (Sentence Timeout)
    _resetSentenceTimeout();

    return true;
  }

  void _resetSentenceTimeout() {
    _sentenceTimeoutTimer?.cancel();
    _sentenceTimeoutTimer = Timer(sentenceTimeout, () {
      if (_words.isNotEmpty && onSentenceReady != null) {
        onSentenceReady!(List.from(_words), List.from(_predictionSequence));
      }
    });
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
  }

  @override
  void dispose() {
    _sentenceTimeoutTimer?.cancel();
    super.dispose();
  }
}
