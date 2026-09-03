import 'package:flutter/material.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/ai_service.dart';
import 'package:ishara/services/local_memory_service.dart';
import 'package:ishara/services/local_model_service.dart';
import 'package:ishara/services/speech_service.dart';

class TranslationController extends ChangeNotifier {
  final LocalMemoryService _memory;
  final LocalModelService _localModel;
  final AIService _aiService;
  final SpeechService _speechService;

  String _translatedText = '';
  String _status = 'جاهز للترجمة';
  bool _isProcessing = false;

  TranslationController(
    this._memory,
    this._localModel,
    this._aiService,
    this._speechService,
  );

  String get translatedText => _translatedText;
  String get status => _status;
  bool get isProcessing => _isProcessing;

  Future<String?> processSequence(List<SignPrediction> sequence, {bool autoSpeak = false}) async {
    if (sequence.isEmpty) return null;
    if (_isProcessing) return null;

    _isProcessing = true;
    _status = 'جارٍ البحث في الذاكرة السريعة...';
    notifyListeners();

    try {
      // 1. التحقق من الذاكرة المحلية الفورية
      final cached = await _memory.lookupSequence(sequence);
      if (cached != null && cached.isNotEmpty) {
        _translatedText = cached;
        _status = 'تمت الترجمة (ذاكرة سريعة ⚡)';
        notifyListeners();
        if (autoSpeak) {
          await _speechService.speak(_translatedText);
        }
        return _translatedText;
      }

      // 2. الترجمة عبر محرك الذكاء الاصطناعي والصياغة اللغوية
      _status = 'جارٍ صياغة الجملة بالذكاء الاصطناعي...';
      notifyListeners();

      final aiResult = await _aiService.translateSequence(sequence);
      if (aiResult != null && aiResult.isNotEmpty) {
        _translatedText = aiResult;
        await _memory.storeSequence(sequence, aiResult, provider: AppConstants.aiProviderKey);
        _status = 'تمت صياغة الجملة بنجاح ✨';
      } else {
        _translatedText = sequence.map((s) => s.label).join(' ');
        _status = 'تمت الترجمة المباشرة';
      }

      if (autoSpeak && _translatedText.isNotEmpty) {
        await _speechService.speak(_translatedText);
      }
      return _translatedText;
    } catch (e) {
      _status = 'خطأ أثناء الترجمة';
      _translatedText = sequence.map((s) => s.label).join(' ');
      return _translatedText;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> clear() async {
    _translatedText = '';
    _status = 'جاهز للترجمة';
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await _memory.dispose();
    await _localModel.dispose();
    await _aiService.dispose();
    super.dispose();
  }
}
