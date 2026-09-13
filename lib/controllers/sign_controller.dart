import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/models/landmarks_model.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/ml_service.dart';
import 'package:ishara/services/motion_analyzer.dart';
import 'package:ishara/services/speech_service.dart';
import 'package:ishara/services/temporal_stabilizer.dart';
import 'package:ishara/services/word_buffer_service.dart';
import 'package:ishara/services/word_only_filter.dart';

class SignProvider extends ChangeNotifier {
  final MLService _mlService;
  final SpeechService _speechService;
  final WordBufferService _wordBuffer = WordBufferService();
  final TemporalStabilizer _temporalStabilizer = TemporalStabilizer();
  final MotionAnalyzer _motionAnalyzer = MotionAnalyzer();

  SignPrediction? _currentRealtimePrediction;
  SignPrediction? _lastStablePrediction;
  SignStabilityState _stabilityState = SignStabilityState.idle;
  bool _isProcessing = false;
  bool _autoSpeakEnabled = false;
  bool _autoTranslateEnabled = true;

  void Function(SignPrediction prediction)? onStableSignDetected;
  void Function(SignStabilityState state, String? label, double confidence)? onStabilityStateChanged;
  Future<void> Function(List<String> words, List<SignPrediction> sequence)? onAutoTranslate;

  SignProvider(this._mlService, this._speechService) {
    _wordBuffer.addListener(notifyListeners);
    _wordBuffer.onSentenceReady = (words, sequence) {
      if (_autoTranslateEnabled && onAutoTranslate != null && words.isNotEmpty) {
        onAutoTranslate!(words, sequence);
      }
    };

    // ربط مستشعر الثبات الزمني
    _temporalStabilizer.onStableSign = (stablePrediction) {
      _lastStablePrediction = stablePrediction;
      _wordBuffer.pushPrediction(stablePrediction);
      if (onStableSignDetected != null) {
        onStableSignDetected!(stablePrediction);
      }
      notifyListeners();
    };

    _temporalStabilizer.onStateChanged = (state, label, confidence) {
      _stabilityState = state;
      if (onStabilityStateChanged != null) {
        onStabilityStateChanged!(state, label, confidence);
      }
      notifyListeners();
    };
  }

  List<String> get wordTokens => _wordBuffer.words;
  List<SignPrediction> get predictionSequence => _wordBuffer.predictionSequence;
  String get textBuffer => _wordBuffer.sentenceRaw;
  SignPrediction? get currentRealtimePrediction => _currentRealtimePrediction;
  SignPrediction? get lastStablePrediction => _lastStablePrediction;
  SignStabilityState get stabilityState => _stabilityState;
  bool get isProcessing => _isProcessing;
  bool get hasText => _wordBuffer.isNotEmpty;
  bool get isModelLoaded => _mlService.isLoaded;
  bool get autoSpeakEnabled => _autoSpeakEnabled;
  bool get autoTranslateEnabled => _autoTranslateEnabled;

  void toggleAutoSpeak() {
    _autoSpeakEnabled = !_autoSpeakEnabled;
    notifyListeners();
  }

  void toggleAutoTranslate() {
    _autoTranslateEnabled = !_autoTranslateEnabled;
    notifyListeners();
  }

  Future<void> loadModel(List<String> labels) async {
    await _mlService.loadModel(labels);
  }

  Future<void> processLandmarks(HandLandmarks? landmarks) async {
    // ── No Hand ➔ Zero Recognition ──
    if (landmarks == null || !landmarks.isValid) {
      _motionAnalyzer.reset();
      _currentRealtimePrediction = null;
      _temporalStabilizer.processPrediction(null, isHandStatic: true);
      _wordBuffer.resetCurrentHand();
      notifyListeners();
      return;
    }

    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // 1. تحليل الحركة (Motion Features & Energy)
      final motion = _motionAnalyzer.analyze(landmarks);

      // إذا بدأت حركة إشارة جديدة واضحة، نتيح لـ TemporalStabilizer السماح بالإشارة التالية
      if (motion.motionEnergy > AppConstants.motionEnergyStartThreshold || motion.averageVelocity > 0.04) {
        _temporalStabilizer.allowNextSignAfterMotion();
      }

      // 2. تشغيل نموذج الاستنتاج مع تمرير خصائص الحركة
      final prediction = await _mlService.predict(landmarks, motionFeatures: motion);

      // 3. ترشيح الحروف المنفردة عبر WordOnlyFilter وتمرير التنبؤ والحركة لآلة الحالة الزمنية
      if (prediction != null && WordOnlyFilter.isValidWord(prediction.label)) {
        _currentRealtimePrediction = prediction;
        _temporalStabilizer.processPrediction(
          prediction,
          motion: motion,
          isHandStatic: motion.isHandStatic,
          isSignBoundary: motion.isSignBoundary,
        );
      } else {
        _currentRealtimePrediction = null;
        _temporalStabilizer.processPrediction(
          null,
          motion: motion,
          isHandStatic: motion.isHandStatic,
          isSignBoundary: motion.isSignBoundary,
        );
      }

      notifyListeners();
    } finally {
      _isProcessing = false;
    }
  }

  void addWord(String word) {
    if (!WordOnlyFilter.isValidWord(word)) return;

    final pred = SignPrediction(
      label: word.trim(),
      confidence: 1.0,
      timestamp: DateTime.now(),
    );
    _lastStablePrediction = pred;
    _wordBuffer.pushPrediction(pred);
    if (onStableSignDetected != null) {
      onStableSignDetected!(pred);
    }
  }

  void removeWordAt(int index) {
    if (index >= 0 && index < _wordBuffer.length) {
      _wordBuffer.deleteLastWord();
    }
  }

  void deleteLastWord() {
    _wordBuffer.deleteLastWord();
  }

  void clearText() {
    _wordBuffer.clear();
    _temporalStabilizer.reset();
    _motionAnalyzer.reset();
    _currentRealtimePrediction = null;
    _lastStablePrediction = null;
    _stabilityState = SignStabilityState.idle;
    notifyListeners();
  }

  Future<void> speakText(String text) async {
    if (text.trim().isEmpty) return;
    await _speechService.speak(text.trim());
  }

  Future<void> stopSpeaking() async {
    await _speechService.stop();
  }

  @override
  void dispose() {
    _wordBuffer.dispose();
    _mlService.dispose();
    _speechService.dispose();
    super.dispose();
  }
}
