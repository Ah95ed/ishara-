import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/models/gloss_result.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/gloss_model_service.dart';
import 'package:ishara/services/temporal_stabilizer.dart';
import 'package:ishara/services/word_only_filter.dart';

/// وحدة التحكم المركزية بالـ Gloss والترجمة (Gloss Controller)
/// تطبق المعمارية المعتمدة:
/// 1. Gloss Buffer داخلي لتجميع الكلمات المؤكدة دون إزعاج المستخدم.
/// 2. Sentence Boundary: ترجمة التسلسل عند توقف اليد أو إشارة الإنهاء إلى جملة عربية نهائية.
class GlossController extends ChangeNotifier {
  final GlossModelService _glossModelService;

  String? _currentSign;
  String? _currentSentence;
  SignStabilityState _stabilityState = SignStabilityState.detecting;
  final List<String> _glossBuffer = [];
  GlossResult? _lastResult;
  Timer? _sentenceCompletionTimer;

  final Duration sentencePauseDuration;

  GlossController(
    this._glossModelService, {
    this.sentencePauseDuration = const Duration(milliseconds: AppConstants.sentencePauseDurationMs),
  }) {
    _glossModelService.addListener(notifyListeners);
  }

  // ────────────────────────────────── Getters للـ Provider ──────────────────────────────────
  String? get currentSign => _currentSign;
  String? get currentSentence => _currentSentence;
  bool get isModelReady => _glossModelService.isReady;
  bool get isGenerating => _glossModelService.isGenerating;
  SignStabilityState get stabilityState => _stabilityState;
  List<String> get bufferedGlossTokens => List.unmodifiable(_glossBuffer);
  GlossResult? get lastResult => _lastResult;
  bool get hasSentence => _currentSentence != null && _currentSentence!.isNotEmpty;
  bool get hasSign => _currentSign != null && _currentSign!.isNotEmpty;
  bool get hasContent => displayText != null && displayText!.isNotEmpty;

  /// النص المراد عرضه للمستخدم (الجملة المصاغة أو الكلمات المعتمدة فوراً)
  String? get displayText {
    if (_currentSentence != null && _currentSentence!.isNotEmpty) {
      return _currentSentence;
    }
    if (_glossBuffer.isNotEmpty) {
      return _glossBuffer.join(' ');
    }
    if (_currentSign != null && _currentSign!.isNotEmpty) {
      return _currentSign;
    }
    return null;
  }

  // ────────────────────────────────── 1. Fast Path ──────────────────────────────────

  /// استلام إشارة مستقرة ومؤكدة قادمة من الـ TemporalStabilizer
  void onStableSign(SignPrediction prediction) {
    if (!WordOnlyFilter.isValidWord(prediction.label)) return;

    final word = prediction.label.trim();
    if (word.isEmpty) return;

    _currentSign = word;
    _stabilityState = SignStabilityState.stable;

    // فحص إشارة الإنهاء السريعة
    if (word == 'إنهاء') {
      _sentenceCompletionTimer?.cancel();
      translateCurrentSequence();
      return;
    }

    // إضافة الكلمة إلى الـ Gloss Buffer الداخلي (مع منع التكرار المتتالي)
    if (_glossBuffer.isEmpty || _glossBuffer.last != word) {
      _glossBuffer.add(word);
      if (_glossBuffer.length > 20) {
        _glossBuffer.removeAt(0);
      }
    }

    notifyListeners();

    // تشغيل مؤقت اكتمال الجملة (Sentence Boundary: 1.3 ثانية من السكون)
    _scheduleSentenceTranslation();
  }

  /// تحديث حالة الكشف اللحظية (detecting / candidate / stable)
  void updateStabilityState(SignStabilityState state, String? candidateLabel, double confidence) {
    if (_stabilityState != state) {
      _stabilityState = state;
      notifyListeners();
    }
  }

  void _scheduleSentenceTranslation() {
    _sentenceCompletionTimer?.cancel();
    _sentenceCompletionTimer = Timer(sentencePauseDuration, () {
      if (_glossBuffer.isNotEmpty) {
        translateCurrentSequence();
      }
    });
  }

  /// ترجمة التسلسل المخزن حالياً عبر نموذج Gemma3 GGUF أو الـ Cache
  Future<void> translateCurrentSequence() async {
    if (_glossBuffer.isEmpty) return;

    final sequence = _glossBuffer.join(' ');
    final result = await _glossModelService.translateGloss(sequence);
    if (result != null) {
      _lastResult = result;
      _currentSentence = result.arabicText;
      notifyListeners();
    }
  }

  /// مسح الجملة الحالية وإعادة تعيين الـ Buffer
  void clearAll() {
    _sentenceCompletionTimer?.cancel();
    _glossBuffer.clear();
    _currentSign = null;
    _currentSentence = null;
    _stabilityState = SignStabilityState.detecting;
    _lastResult = null;
    notifyListeners();
  }

  /// مسح آخر كلمة من الـ Buffer
  void removeLastSign() {
    if (_glossBuffer.isNotEmpty) {
      _glossBuffer.removeLast();
      _currentSign = _glossBuffer.isNotEmpty ? _glossBuffer.last : null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sentenceCompletionTimer?.cancel();
    _glossModelService.removeListener(notifyListeners);
    super.dispose();
  }
}
