import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ishara/constants/sign_recognition_config.dart';
import 'package:ishara/models/gloss_result.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/gloss_model_service.dart';
import 'package:ishara/services/temporal_stabilizer.dart';
import 'package:ishara/services/word_only_filter.dart';

/// وحدة التحكم المركزية بالـ Gloss والترجمة المفصولة (Gloss Controller)
///
/// تفصل التعرف عن الترجمة:
/// 1. Gloss Buffer: تجميع الكلمات المعتمدة (COMMITTED) في قائمة متسلسلة.
/// 2. عدم استدعاء Gloss2Text فورياً لكل كلمة للحفاظ على الأداء والبطارية وسياق الجملة.
/// 3. عرض نص الـ Gloss حياً للمستخدم أثناء التجميع (مثلاً: "أنا ... أحبك ...").
/// 4. شروط اكتمال الجملة وترجمتها:
///    - سكون نهاية الجملة (3000ms من التوقف التام).
///    - الوصول للحد الأقصى للكلمات (7 كلمات).
///    - ضغطة زر يدوي "ترجم الآن" من المستخدم.
///    - إشارة إنهاء ('إنهاء').
class GlossController extends ChangeNotifier {
  final GlossModelService _glossModelService;

  String? _currentSign;
  String? _currentSentence;
  SignStabilityState _stabilityState = SignStabilityState.idle;
  final List<String> _glossBuffer = [];
  GlossResult? _lastResult;
  Timer? _sentenceCompletionTimer;

  final Duration sentencePauseDuration;
  final int maxBufferWords;

  GlossController(
    this._glossModelService, {
    this.sentencePauseDuration = const Duration(milliseconds: SignRecognitionConfig.sentenceEndSilenceMs),
    this.maxBufferWords = SignRecognitionConfig.maxBufferWords,
  }) {
    _glossModelService.addListener(notifyListeners);
  }

  // ──────────────────────────────── Getters للواجهة والمزود ────────────────────────────────
  String? get currentSign => _currentSign;
  String? get currentSentence => _currentSentence;
  bool get isModelReady => _glossModelService.isReady;
  bool get isGenerating => _glossModelService.isGenerating;
  SignStabilityState get stabilityState => _stabilityState;
  List<String> get bufferedGlossTokens => List.unmodifiable(_glossBuffer);
  GlossResult? get lastResult => _lastResult;
  bool get hasSentence => _currentSentence != null && _currentSentence!.isNotEmpty;
  bool get hasSign => _currentSign != null && _currentSign!.isNotEmpty;
  bool get hasBuffer => _glossBuffer.isNotEmpty;
  bool get hasContent => displayText != null && displayText!.isNotEmpty;

  /// النص الحي المعروض للمستخدم
  /// أثناء التجميع: يعرض الكلمات المجمعة حياً (مثال: "أنا ... أحبك ...")
  /// بعد الترجمة: يُستبدل بالجملة النهائية المصاغة عبر Gemma3 GGUF
  String? get displayText {
    if (_currentSentence != null && _currentSentence!.isNotEmpty) {
      return _currentSentence;
    }
    if (_glossBuffer.isNotEmpty) {
      return _glossBuffer.join(' ... ');
    }
    if (_currentSign != null && _currentSign!.isNotEmpty) {
      return _currentSign;
    }
    return null;
  }

  /// نص الـ Gloss الخام المجمع حالياً
  String get rawGlossText => _glossBuffer.join(' ');

  // ──────────────────────────────── 1. مسار تجميع الـ Gloss ────────────────────────────────

  /// استلام كلمة معتمدة قادمة من آلة الحالة الزمنية (COMMITTED)
  void onStableSign(SignPrediction prediction) {
    if (!WordOnlyFilter.isValidWord(prediction.label)) return;

    final word = prediction.label.trim();
    if (word.isEmpty) return;

    _currentSign = word;
    _stabilityState = SignStabilityState.committed;

    // فحص إشارة الإنهاء السريعة
    if (word == 'إنهاء') {
      _sentenceCompletionTimer?.cancel();
      translateCurrentSequence();
      return;
    }

    // إضافة الكلمة إلى الـ Gloss Buffer (مع منع التكرار المباشر)
    if (_glossBuffer.isEmpty || _glossBuffer.last != word) {
      _glossBuffer.add(word);
      // عند إضافة كلمة جديدة بعد جملة سابقة، نفرغ الجملة السابقة ليعود العرض الحي للـ Gloss
      _currentSentence = null;
    }

    notifyListeners();

    // فحص الحد الأقصى لكلمات الـ Buffer (شرط الاكتمال رقم 2)
    if (_glossBuffer.length >= maxBufferWords) {
      _sentenceCompletionTimer?.cancel();
      translateCurrentSequence();
      return;
    }

    // ضبط مؤقت سكون نهاية الجملة (شرط الاكتمال رقم 1: 3 ثوانٍ)
    _scheduleSentenceTranslation();
  }

  /// تحديث حالة آلة الحالة الزمنية
  void updateStabilityState(SignStabilityState state, String? candidateLabel, double confidence) {
    if (_stabilityState != state) {
      _stabilityState = state;
      notifyListeners();
    }
  }

  void _scheduleSentenceTranslation() {
    _sentenceCompletionTimer?.cancel();
    _sentenceCompletionTimer = Timer(sentencePauseDuration, () {
      if (_glossBuffer.isNotEmpty && !isGenerating) {
        translateCurrentSequence();
      }
    });
  }

  // ──────────────────────────────── 2. ترجمة تسلسل الجملة ────────────────────────────────

  /// زر يدوي اختياري: ترجمة الجملة فوراً (شرط الاكتمال رقم 3)
  void triggerManualTranslation() {
    _sentenceCompletionTimer?.cancel();
    if (_glossBuffer.isNotEmpty && !isGenerating) {
      translateCurrentSequence();
    }
  }

  /// استدعاء نموذج Gemma3 GGUF (Gloss2Text) لترجمة تسلسل الـ Gloss ككتلة سياقية كاملة
  Future<void> translateCurrentSequence() async {
    if (_glossBuffer.isEmpty) return;

    final sequence = _glossBuffer.join(' ');
    final result = await _glossModelService.translateGloss(sequence);

    if (result != null) {
      _lastResult = result;
      _currentSentence = result.arabicText;
      // نحتفظ بكلمات الـ Buffer كسياق أو يمكن مسحها بعد نجاح الصياغة
      notifyListeners();
    }
  }

  /// مسح الجملة والـ Buffer بالكامل
  void clearAll() {
    _sentenceCompletionTimer?.cancel();
    _glossBuffer.clear();
    _currentSign = null;
    _currentSentence = null;
    _stabilityState = SignStabilityState.idle;
    _lastResult = null;
    notifyListeners();
  }

  /// مسح آخر كلمة مضافة للـ Buffer
  void removeLastSign() {
    if (_glossBuffer.isNotEmpty) {
      _glossBuffer.removeLast();
      _currentSign = _glossBuffer.isNotEmpty ? _glossBuffer.last : null;
      _currentSentence = null;
      notifyListeners();
      if (_glossBuffer.isNotEmpty) {
        _scheduleSentenceTranslation();
      } else {
        _sentenceCompletionTimer?.cancel();
      }
    }
  }

  @override
  void dispose() {
    _sentenceCompletionTimer?.cancel();
    _glossModelService.removeListener(notifyListeners);
    super.dispose();
  }
}
