import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ishara/models/gloss_result.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/gloss_model_service.dart';
import 'package:ishara/services/temporal_stabilizer.dart';

/// وحدة التحكم المركزية بالـ Gloss والترجمة (Gloss Controller)
/// تطبق المعمارية المزدوجة:
/// 1. Fast Path: عرض الإشارة المستقرة فوراً تحت الكاميرا دون استدعاء LLM.
/// 2. Sentence Path: تجميع الإشارات المركبة واستدعاء نموذج GGUF عند توالي عدة إشارات.
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
    this.sentencePauseDuration = const Duration(milliseconds: 1400),
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

  // ────────────────────────────────── 1. Fast Path ──────────────────────────────────

  /// استلام إشارة مستقرة ومؤكدة قادمة من الـ TemporalStabilizer
  void onStableSign(SignPrediction prediction) {
    final word = prediction.label.trim();
    if (word.isEmpty) return;

    // Fast Path الفوري: تحديث الإشارة اللحظية دون تشغيل LLM
    _currentSign = word;
    _stabilityState = SignStabilityState.stable;

    // إضافة الكلمة إلى الـ Buffer للجملة
    if (_glossBuffer.isEmpty || _glossBuffer.last != word) {
      _glossBuffer.add(word);
      if (_glossBuffer.length > 20) {
        _glossBuffer.removeAt(0);
      }
    }

    notifyListeners();

    // ────────────────────────────────── 2. Sentence Path ──────────────────────────────────
    // إذا كان لدينا إشارة واحدة فقط: لا نطلق الـ LLM، فالـ Fast Path كافٍ تماماً.
    // إذا كان لدينا تسلسل من إشارتين أو أكثر: نشغّل مؤقت اكتمال الجملة
    if (_glossBuffer.length >= 2) {
      _scheduleSentenceTranslation();
    }
  }

  /// تحديث حالة الكشف اللحظية (detecting / candidate / stable)
  void updateStabilityState(SignStabilityState state, String? candidateLabel, double confidence) {
    if (_stabilityState != state) {
      _stabilityState = state;
      // إذا كانت الثقة منخفضة أو جارٍ الكشف، لا نلغي الكلمة القديمة فجأة، فقط نحدّث المؤشر
      notifyListeners();
    }
  }

  void _scheduleSentenceTranslation() {
    _sentenceCompletionTimer?.cancel();
    _sentenceCompletionTimer = Timer(sentencePauseDuration, () {
      if (_glossBuffer.length >= 2) {
        translateCurrentSequence();
      }
    });
  }

  /// ترجمة التسلسل المخزن حالياً عبر نموذج Gemma3 GGUF
  Future<void> translateCurrentSequence() async {
    if (_glossBuffer.length < 2) return;

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
